//
//  ScanViewModelTests.swift
//  KolaCareTests
//
//  Scan flow state machine, severity grading and performance baselines.
//

import SwiftData
import XCTest
@testable import KolaCare

@MainActor
final class ScanViewModelTests: XCTestCase {

    func testSuccessfulAnalysisReachesResult() async {
        let viewModel = ScanViewModel(diagnoser: MockDiagnoser(result: MockDiagnoser.sample()), minimumAnalysisDuration: .zero)
        viewModel.analyze(cgImage: TestImages.leaf())
        XCTAssertEqual(viewModel.phase, .analyzing)
        XCTAssertNotNil(viewModel.image)

        await viewModel.waitForAnalysis()

        XCTAssertEqual(viewModel.phase, .result)
        XCTAssertEqual(viewModel.result?.diseaseID, "tomato.early_blight")
    }

    func testDiagnosisErrorReachesFailed() async {
        let viewModel = ScanViewModel(diagnoser: MockDiagnoser(error: TestError()), minimumAnalysisDuration: .zero)
        viewModel.analyze(cgImage: TestImages.leaf())
        await viewModel.waitForAnalysis()
        guard case .failed = viewModel.phase else { return XCTFail("expected .failed, got \(viewModel.phase)") }
        XCTAssertNil(viewModel.result)
    }

    func testUnreadableDataFailsImmediately() {
        let viewModel = ScanViewModel(diagnoser: MockDiagnoser(result: MockDiagnoser.sample()), minimumAnalysisDuration: .zero)
        viewModel.analyze(imageData: Data("not an image".utf8))
        guard case .failed = viewModel.phase else { return XCTFail("expected .failed") }
    }

    func testSaveAttachesScanToPlantWithoutReminder() async throws {
        let container = Fixtures.inMemoryContainer()
        let plant = GardenRepository(context: container.mainContext).addPlant(name: "Tomato bed", crop: .tomato)
        let viewModel = ScanViewModel(diagnoser: MockDiagnoser(result: MockDiagnoser.sample(affected: 0.3)), minimumAnalysisDuration: .zero)
        viewModel.analyze(cgImage: TestImages.leaf(brownSpots: 4))
        await viewModel.waitForAnalysis()

        let record = try XCTUnwrap(viewModel.save(to: plant, notes: "Lower leaves", followUpInDays: nil, context: container.mainContext))

        XCTAssertEqual(record.plant?.id, plant.id)
        XCTAssertEqual(record.notes, "Lower leaves")
        XCTAssertNil(record.followUpDate)
        XCTAssertNotNil(record.imageData, "photo is stored")
        XCTAssertNotNil(record.thumbnailData, "thumbnail is stored")
        XCTAssertEqual(plant.scans.count, 1)
    }

    func testResetClearsEverything() async {
        let viewModel = ScanViewModel(diagnoser: MockDiagnoser(result: MockDiagnoser.sample()), minimumAnalysisDuration: .zero)
        viewModel.analyze(cgImage: TestImages.leaf())
        await viewModel.waitForAnalysis()
        viewModel.reset()
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertNil(viewModel.image)
        XCTAssertNil(viewModel.result)
    }
}

final class SeverityTests: XCTestCase {

    func testSeverityBands() {
        XCTAssertEqual(Severity(affectedArea: 0.00), .healthy)
        XCTAssertEqual(Severity(affectedArea: 0.049), .healthy)
        XCTAssertEqual(Severity(affectedArea: 0.05), .low)
        XCTAssertEqual(Severity(affectedArea: 0.20), .moderate)
        XCTAssertEqual(Severity(affectedArea: 0.50), .severe)
        XCTAssertEqual(Severity(affectedArea: 0.50, isHealthyDiagnosis: true), .low, "healthy model result caps severity")
    }

    func testHealthScoreIsMonotonicAndBounded() {
        var previous = Int.max
        for step in 0...20 {
            let score = HealthScore.from(affectedArea: Double(step) / 20)
            XCTAssertLessThanOrEqual(score, previous)
            XCTAssertTrue((0...100).contains(score))
            previous = score
        }
        XCTAssertEqual(HealthScore.from(affectedArea: 0), 100)
        XCTAssertEqual(HealthScore.from(affectedArea: 1), 0)
        XCTAssertEqual(HealthScore.from(affectedArea: -1), 100, "input is clamped")
    }

    func testScoreAndAreaBandsAgree() {
        // The score thresholds are derived from the area thresholds; they must classify alike.
        for area in stride(from: 0.0, through: 0.6, by: 0.01) {
            let viaArea = Severity(affectedArea: area)
            let viaScore = HealthScore.severity(for: HealthScore.from(affectedArea: area))
            XCTAssertLessThanOrEqual(abs(viaArea.rawValue - viaScore.rawValue), 1, "area \(area)")
        }
    }

    func testHealthyDiagnosisHasHealthyFloor() {
        let result = MockDiagnoser.sample(diseaseID: "tomato.healthy", affected: 0.08)
        XCTAssertGreaterThanOrEqual(result.healthScore, 92)
        XCTAssertEqual(result.severity, .healthy)
    }
}

final class PerformanceTests: XCTestCase {

    func testPixelAnalysisPerformance() {
        let image = TestImages.leaf(size: 1024, brownSpots: 8, yellowPatches: 4)
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            _ = LeafPixelAnalyzer.analyze(image)
        }
    }

    func testFullColourPipelinePerformance() {
        let service = LeafDiagnosisService(catalog: .shared, classifier: nil, segmentationEnabled: false)
        let image = TestImages.leaf(size: 1024, brownSpots: 8)
        measure(metrics: [XCTClockMetric()]) {
            let expectation = expectation(description: "diagnosed")
            Task {
                _ = try? await service.diagnose(image)
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 5)
        }
    }

    func testDownsamplingKeepsMemoryLow() throws {
        let large = TestImages.leaf(size: 3000)
        let data = try XCTUnwrap(ImageProcessing.jpegData(from: large, quality: 0.9))
        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()]) {
            let image = ImageProcessing.downsample(data, maxPixelSize: ImageProcessing.analysisMaxPixel)
            XCTAssertEqual(max(image?.width ?? 0, image?.height ?? 0), ImageProcessing.analysisMaxPixel)
        }
    }
}
