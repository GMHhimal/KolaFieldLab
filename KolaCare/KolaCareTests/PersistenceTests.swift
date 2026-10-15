//
//  PersistenceTests.swift
//  KolaCareTests
//
//  SwiftData model behaviour against an in-memory store.
//

import SwiftData
import XCTest
@testable import KolaCare

@MainActor
final class PersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: GardenRepository!

    override func setUp() async throws {
        try await super.setUp()
        container = Fixtures.inMemoryContainer()
        repository = GardenRepository(context: container.mainContext)
    }

    override func tearDown() async throws {
        repository = nil
        container = nil
        try await super.tearDown()
    }

    private func plantCount() throws -> Int { try container.mainContext.fetchCount(FetchDescriptor<Plant>()) }
    private func scanCount() throws -> Int { try container.mainContext.fetchCount(FetchDescriptor<ScanRecord>()) }

    func testAddPlantTrimsNameAndStoresCrop() throws {
        let plant = repository.addPlant(name: "  Tomato bed A  ", crop: .tomato, latitude: 7.87, longitude: 80.65)
        XCTAssertEqual(plant.name, "Tomato bed A")
        XCTAssertEqual(plant.crop, .tomato)
        XCTAssertEqual(plant.coordinate?.latitude ?? 0, 7.87, accuracy: 0.0001)
        XCTAssertNil(plant.healthScore, "unscanned plants have no score")
        XCTAssertEqual(try plantCount(), 1)
    }

    func testLatestScanDrivesPlantHealth() throws {
        let plant = repository.addPlant(name: "Chilli", crop: .chilli)
        let old = Date(timeIntervalSinceNow: -7 * 86_400)
        repository.addScan(to: plant, result: MockDiagnoser.sample(affected: 0.40), photo: nil, thumbnail: nil, date: old)
        repository.addScan(to: plant, result: MockDiagnoser.sample(affected: 0.05), photo: nil, thumbnail: nil)

        XCTAssertEqual(plant.scans.count, 2)
        XCTAssertEqual(plant.sortedScans.first?.affectedArea ?? 0, 0.05, accuracy: 0.0001, "newest first")
        XCTAssertEqual(plant.healthScore, HealthScore.from(affectedArea: 0.05))
        XCTAssertEqual(plant.severity, .healthy)
    }

    func testDeletingPlantCascadesToScans() throws {
        let plant = repository.addPlant(name: "Potato plot", crop: .potato)
        repository.addScan(to: plant, result: MockDiagnoser.sample(), photo: nil, thumbnail: nil)
        repository.addScan(to: plant, result: MockDiagnoser.sample(), photo: nil, thumbnail: nil)
        XCTAssertEqual(try scanCount(), 2)

        repository.delete(plant)

        XCTAssertEqual(try plantCount(), 0)
        XCTAssertEqual(try scanCount(), 0, "scans are deleted with their plant")
    }

    func testDeletingScanKeepsPlant() throws {
        let plant = repository.addPlant(name: "Paddy", crop: .rice)
        let scan = repository.addScan(to: plant, result: MockDiagnoser.sample(), photo: nil, thumbnail: nil)
        repository.delete(scan)
        XCTAssertEqual(try plantCount(), 1)
        XCTAssertEqual(try scanCount(), 0)
        XCTAssertTrue(plant.scans.isEmpty)
    }

    func testTreatmentChecklistPersists() throws {
        let plant = repository.addPlant(name: "Tomato", crop: .tomato)
        let scan = repository.addScan(to: plant, result: MockDiagnoser.sample(), photo: nil, thumbnail: nil)
        scan.toggleStep(0)
        scan.toggleStep(2)
        scan.toggleStep(0)
        try container.mainContext.save()

        let fetched = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<ScanRecord>()).first)
        XCTAssertEqual(fetched.completedSteps, [2])
        XCTAssertEqual(fetched.treatmentProgress(totalSteps: 4), 0.25, accuracy: 0.0001)
        XCTAssertEqual(fetched.treatmentProgress(totalSteps: 0), 1, "no steps → nothing left to do")
    }

    func testLookupByID() {
        let plant = repository.addPlant(name: "Maize", crop: .corn)
        XCTAssertEqual(repository.plant(withID: plant.id)?.name, "Maize")
        XCTAssertNil(repository.plant(withID: UUID()))
    }

    func testDemoSeederAndEraseAll() throws {
        DemoDataSeeder.seed(into: container.mainContext)
        XCTAssertEqual(try plantCount(), 4)
        XCTAssertGreaterThan(try scanCount(), 4)

        repository.eraseAll()
        XCTAssertEqual(try plantCount(), 0)
        XCTAssertEqual(try scanCount(), 0)
    }

    func testCSVExportEscapesFields() throws {
        let plant = repository.addPlant(name: "Bed \"A\", north", crop: .tomato, plotName: "Home")
        repository.addScan(to: plant, result: MockDiagnoser.sample(), photo: nil, thumbnail: nil, notes: "sprayed, then\nwaited")

        let csv = GardenCSVExporter.csv(for: [plant], catalog: .shared)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines.first.map(String.init), GardenCSVExporter.header)
        XCTAssertTrue(csv.contains("\"Bed \"\"A\"\", north\""), "quotes doubled and field wrapped")
        XCTAssertTrue(csv.contains("Early blight"))
        XCTAssertTrue(csv.contains("\"sprayed, then\nwaited\""))
    }
}
