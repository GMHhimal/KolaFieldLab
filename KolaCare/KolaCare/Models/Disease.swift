//
//  Disease.swift
//  KolaCare
//
//  Value types describing the bundled disease catalogue (Resources/diseases.json).
//

import SwiftUI

/// Text available in English, Sinhala and Tamil. Falls back to English.
struct LocalizedText: Codable, Hashable, Sendable {
    let en: String
    let si: String?
    let ta: String?

    /// The string for the language the app is currently running in.
    var current: String { value(for: Bundle.main.preferredLocalizations.first ?? "en") }

    func value(for languageCode: String) -> String {
        switch languageCode.prefix(2) {
        case "si": return si ?? en
        case "ta": return ta ?? en
        default: return en
        }
    }
}

enum PathogenType: String, Codable, CaseIterable, Sendable {
    case fungal, oomycete, bacterial, viral, pest, nutrient, healthy

    var title: LocalizedStringResource {
        switch self {
        case .fungal: "Fungal"
        case .oomycete: "Water mould"
        case .bacterial: "Bacterial"
        case .viral: "Viral"
        case .pest: "Pest"
        case .nutrient: "Nutrient / stress"
        case .healthy: "Healthy"
        }
    }

    var symbol: String {
        switch self {
        case .fungal: "allergens"
        case .oomycete: "drop.triangle"
        case .bacterial: "microbe"
        case .viral: "circle.hexagongrid"
        case .pest: "ant"
        case .nutrient: "leaf.arrow.triangle.circlepath"
        case .healthy: "checkmark.seal"
        }
    }

    var tint: Color {
        switch self {
        case .fungal: .orange
        case .oomycete: .indigo
        case .bacterial: .pink
        case .viral: .purple
        case .pest: .brown
        case .nutrient: .yellow
        case .healthy: .green
        }
    }
}

/// Weather conditions under which a disease (or pest) is likely to develop.
/// Used by `DiseaseRiskEngine` against the hourly forecast.
struct RiskProfile: Codable, Hashable, Sendable {
    let minTemp: Double
    let maxTemp: Double
    /// Disease needs wet conditions: humidity at or above this, or rain.
    let minHumidity: Double?
    /// Pest needs dry conditions: humidity at or below this and no rain.
    let maxHumidity: Double?
    /// Favourable hours (within the forecast window) that make the risk "high".
    let hoursForHighRisk: Int
}

struct Disease: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let crop: Crop
    let type: PathogenType
    let pathogen: String
    let names: LocalizedText
    let summary: String
    let symptoms: [String]
    let favourableConditions: String
    let organicTreatment: [String]
    let chemicalTreatment: [String]
    let prevention: [String]
    /// Class labels emitted by the CoreML model that map to this entry.
    let modelLabels: [String]
    /// 0 = not contagious … 3 = spreads very quickly.
    let contagiousness: Int
    let riskProfile: RiskProfile?

    var name: String { names.current }
    var isHealthy: Bool { type == .healthy }

    /// Every treatment step, organic first. Indices are stored on `ScanRecord.completedSteps`.
    var treatmentPlan: [String] { organicTreatment + chemicalTreatment }
}

struct DiseaseCatalogFile: Codable {
    let version: Int
    let diseases: [Disease]
}
