//
//  CatalogAndRiskTests.swift
//  KolaCareTests
//
//  Disease catalogue integrity and the weather-driven risk engine.
//

import XCTest
@testable import KolaCare

final class DiseaseCatalogTests: XCTestCase {
    private let catalog = DiseaseCatalog.shared

    func testBundledCatalogueLoads() {
        XCTAssertGreaterThanOrEqual(catalog.diseases.count, 25)
        XCTAssertEqual(Set(catalog.diseases.map(\.id)).count, catalog.diseases.count, "ids must be unique")
    }

    func testEveryDiseaseHasActionableGuidance() {
        for disease in catalog.diseases {
            XCTAssertFalse(disease.names.en.isEmpty, disease.id)
            XCTAssertFalse(disease.symptoms.isEmpty, "\(disease.id) needs symptoms")
            XCTAssertFalse(disease.prevention.isEmpty, "\(disease.id) needs prevention")
            if !disease.isHealthy {
                XCTAssertFalse(disease.organicTreatment.isEmpty, "\(disease.id) needs an organic option")
            }
            XCTAssertNotNil(disease.names.si, "\(disease.id) needs a Sinhala name")
            XCTAssertNotNil(disease.names.ta, "\(disease.id) needs a Tamil name")
        }
    }

    func testPlantVillageLabelsMapToCatalogue() {
        let labels = [
            "Tomato___Early_blight", "Tomato___Late_blight", "Tomato___Leaf_Mold", "Tomato___Septoria_leaf_spot",
            "Tomato___Bacterial_spot", "Tomato___Tomato_Yellow_Leaf_Curl_Virus", "Tomato___Tomato_mosaic_virus",
            "Tomato___Spider_mites Two-spotted_spider_mite", "Tomato___Target_Spot", "Tomato___healthy",
            "Potato___Early_blight", "Potato___Late_blight", "Potato___healthy",
            "Pepper,_bell___Bacterial_spot", "Pepper,_bell___healthy",
            "Corn_(maize)___Common_rust_", "Corn_(maize)___Northern_Leaf_Blight",
            "Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot", "Corn_(maize)___healthy",
            "Rice___Leaf_Blast", "Rice___Brown_Spot", "Rice___Bacterial_leaf_blight", "Rice___Healthy"
        ]
        for label in labels {
            XCTAssertNotNil(catalog.disease(forModelLabel: label), "no catalogue entry for model label \(label)")
        }
    }

    func testLabelNormalisationIsForgiving() {
        XCTAssertEqual(catalog.disease(forModelLabel: "corn maize common rust")?.id, "corn.common_rust")
        XCTAssertEqual(catalog.disease(forModelLabel: "TOMATO___EARLY_BLIGHT")?.id, "tomato.early_blight")
        XCTAssertNil(catalog.disease(forModelLabel: "banana___sigatoka"))
    }

    func testSearchMatchesNamesSymptomsAndPathogens() {
        XCTAssertTrue(catalog.search("concentric").contains { $0.id == "tomato.early_blight" }, "symptom text")
        XCTAssertTrue(catalog.search("Phytophthora").contains { $0.id == "potato.late_blight" }, "pathogen")
        XCTAssertTrue(catalog.search("blast").contains { $0.id == "rice.blast" }, "name")
        XCTAssertTrue(catalog.search("", crop: .rice).allSatisfy { $0.crop == .rice })
        XCTAssertTrue(catalog.search("", type: .viral).allSatisfy { $0.type == .viral })
        XCTAssertFalse(catalog.search("").contains { $0.crop == .other }, "generic entries are hidden from the library")
    }

    func testLocalizedTextFallsBackToEnglish() {
        let text = LocalizedText(en: "Early blight", si: "පෙර අංගමාරය", ta: nil)
        XCTAssertEqual(text.value(for: "si"), "පෙර අංගමාරය")
        XCTAssertEqual(text.value(for: "ta"), "Early blight")
        XCTAssertEqual(text.value(for: "fr"), "Early blight")
    }

    func testWeatherSensitiveDiseasesFollowCrops() {
        let diseases = catalog.weatherSensitiveDiseases(for: [.potato])
        XCTAssertFalse(diseases.isEmpty)
        XCTAssertTrue(diseases.allSatisfy { $0.crop == .potato && $0.riskProfile != nil })
    }
}

final class DiseaseRiskEngineTests: XCTestCase {
    private let engine = DiseaseRiskEngine()
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let lateBlight = RiskProfile(minTemp: 10, maxTemp: 25, minHumidity: 90, maxHumidity: nil, hoursForHighRisk: 10)
    private let spiderMites = RiskProfile(minTemp: 27, maxTemp: 40, minHumidity: nil, maxHumidity: 60, hoursForHighRisk: 24)

    private func hours(_ count: Int, temperature: Double, humidity: Double, rain: Double = 0) -> [WeatherForecast.Hour] {
        (0..<count).map {
            WeatherForecast.Hour(date: start.addingTimeInterval(Double($0) * 3600),
                                 temperature: temperature, humidity: humidity, precipitation: rain)
        }
    }

    func testCoolHumidHoursMakeLateBlightHigh() {
        let favourable = engine.favourableHours(for: lateBlight, in: hours(12, temperature: 18, humidity: 95))
        XCTAssertEqual(favourable, 12)
        XCTAssertEqual(engine.level(favourableHours: favourable, profile: lateBlight), .high)
    }

    func testDryOrHotWeatherIsLowRisk() {
        XCTAssertEqual(engine.favourableHours(for: lateBlight, in: hours(24, temperature: 18, humidity: 60)), 0)
        XCTAssertEqual(engine.favourableHours(for: lateBlight, in: hours(24, temperature: 31, humidity: 95)), 0)
    }

    func testRainCountsAsLeafWetness() {
        XCTAssertEqual(engine.favourableHours(for: lateBlight, in: hours(5, temperature: 20, humidity: 70, rain: 1.2)), 5)
    }

    func testDryLovingPestsNeedDryHours() {
        XCTAssertEqual(engine.favourableHours(for: spiderMites, in: hours(6, temperature: 32, humidity: 45)), 6)
        XCTAssertEqual(engine.favourableHours(for: spiderMites, in: hours(6, temperature: 32, humidity: 45, rain: 2)), 0,
                       "rain suppresses mites")
    }

    func testRiskBands() {
        XCTAssertEqual(engine.level(favourableHours: 0, profile: lateBlight), .low)
        XCTAssertEqual(engine.level(favourableHours: 4, profile: lateBlight), .low)
        XCTAssertEqual(engine.level(favourableHours: 5, profile: lateBlight), .moderate)
        XCTAssertEqual(engine.level(favourableHours: 9, profile: lateBlight), .moderate)
        XCTAssertEqual(engine.level(favourableHours: 10, profile: lateBlight), .high)
    }

    func testOnlyTheNext48HoursAreConsidered() {
        // 72 humid hours, but only 48 fall in the window.
        let forecast = Fixtures.forecast(hours: Array(repeating: (temperature: 18.0, humidity: 95.0, rain: 0.0), count: 72), start: start)
        let disease = DiseaseCatalog.shared.disease(id: "potato.late_blight")!
        let risk = engine.assess(forecast, diseases: [disease], now: start).first
        XCTAssertEqual(risk?.favourableHours, 48)
        XCTAssertEqual(risk?.level, .high)
    }

    func testAssessmentIsSortedByUrgency() {
        let forecast = Fixtures.forecast(hours: Array(repeating: (temperature: 18.0, humidity: 95.0, rain: 0.0), count: 48), start: start)
        let diseases = DiseaseCatalog.shared.weatherSensitiveDiseases(for: [.tomato, .potato, .rice])
        let risks = engine.assess(forecast, diseases: diseases, now: start)
        XCTAssertEqual(risks.count, diseases.count)
        XCTAssertEqual(risks.map(\.level), risks.map(\.level).sorted(by: >))
        XCTAssertEqual(risks.first?.level, .high)
    }

    func testWetHourCount() {
        let forecast = Fixtures.forecast(hours: [(25.0, 95.0, 0.0), (25.0, 70.0, 0.5), (25.0, 70.0, 0.0), (25.0, 89.0, 0.0)], start: start)
        XCTAssertEqual(engine.wetHours(in: forecast, now: start), 2)
    }
}
