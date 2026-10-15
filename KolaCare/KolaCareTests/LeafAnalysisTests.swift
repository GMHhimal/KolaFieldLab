//
//  LeafAnalysisTests.swift
//  KolaCareTests
//
//  Pixel classification, symptom measurement and the diagnosis pipeline.
//

import UIKit
import XCTest
@testable import KolaCare

final class LeafPixelAnalyzerTests: XCTestCase {

    func testClassifiesTypicalColours() {
        XCTAssertEqual(LeafPixelAnalyzer.classify(red: 0.20, green: 0.55, blue: 0.20), .healthy, "leaf green")
        XCTAssertEqual(LeafPixelAnalyzer.classify(red: 0.60, green: 0.70, blue: 0.20), .healthy, "yellow-green is still healthy")
        XCTAssertEqual(LeafPixelAnalyzer.classify(red: 0.86, green: 0.80, blue: 0.26), .chlorotic, "chlorotic yellow")
        XCTAssertEqual(LeafPixelAnalyzer.classify(red: 0.40, green: 0.25, blue: 0.11), .necrotic, "necrotic brown")
        XCTAssertEqual(LeafPixelAnalyzer.classify(red: 0.30, green: 0.08, blue: 0.10), .necrotic, "reddish-brown lesion")
        XCTAssertEqual(LeafPixelAnalyzer.classify(red: 0.95, green: 0.95, blue: 0.95), .background, "white paper")
        XCTAssertEqual(LeafPixelAnalyzer.classify(red: 0.93, green: 0.91, blue: 0.84), .background, "beige background")
        XCTAssertEqual(LeafPixelAnalyzer.classify(red: 0.03, green: 0.03, blue: 0.03), .background, "deep shadow")
        XCTAssertEqual(LeafPixelAnalyzer.classify(red: 0.20, green: 0.30, blue: 0.85), .background, "blue sky")
    }

    func testHealthyLeafHasNoSymptoms() {
        let analysis = LeafPixelAnalyzer.analyze(TestImages.leaf())
        XCTAssertLessThan(analysis.metrics.chlorosisFraction, 0.02)
        XCTAssertLessThan(analysis.metrics.necrosisFraction, 0.02)
        XCTAssertEqual(analysis.metrics.leafCoverage, 0.377, accuracy: 0.05, "ellipse covers ~37.7 % of the frame")
        XCTAssertNil(analysis.lesionMap, "no lesions → no overlay")
    }

    func testBrownSpotsAreMeasuredAsDeadTissue() {
        let analysis = LeafPixelAnalyzer.analyze(TestImages.leaf(brownSpots: 6))
        XCTAssertGreaterThan(analysis.metrics.necrosisFraction, 0.05)
        XCTAssertLessThan(analysis.metrics.necrosisFraction, 0.30)
        XCTAssertGreaterThan(analysis.metrics.necrosisFraction, analysis.metrics.chlorosisFraction)
        XCTAssertNotNil(analysis.lesionMap)
    }

    func testYellowPatchesAreMeasuredAsChlorosis() {
        let analysis = LeafPixelAnalyzer.analyze(TestImages.leaf(yellowPatches: 6))
        XCTAssertGreaterThan(analysis.metrics.chlorosisFraction, 0.05)
        XCTAssertGreaterThan(analysis.metrics.chlorosisFraction, analysis.metrics.necrosisFraction)
    }

    func testLesionMapKeepsPhotoAspectRatio() throws {
        let analysis = LeafPixelAnalyzer.analyze(TestImages.leaf(brownSpots: 4))
        let map = try XCTUnwrap(analysis.lesionMap)
        XCTAssertEqual(map.width, LeafPixelAnalyzer.sampleSize)
        XCTAssertEqual(map.height, LeafPixelAnalyzer.sampleSize, "square input → square map")
    }

    func testBlankImageHasNoLeaf() {
        let analysis = LeafPixelAnalyzer.analyze(TestImages.solid(1, 1, 1))
        XCTAssertEqual(analysis.metrics.leafCoverage, 0)
        XCTAssertEqual(analysis.metrics.affectedArea, 0)
    }

    func testHeuristicDiagnosis() {
        func metrics(chlorosis: Double, necrosis: Double) -> LeafMetrics {
            LeafMetrics(leafCoverage: 0.4, greenFraction: 1 - chlorosis - necrosis, chlorosisFraction: chlorosis,
                        necrosisFraction: necrosis, meanLuminance: 0.5, usedSegmentation: false)
        }
        XCTAssertEqual(LeafPixelAnalyzer.heuristicDiagnosis(for: metrics(chlorosis: 0.01, necrosis: 0.01)).diseaseID, "general.healthy")
        XCTAssertEqual(LeafPixelAnalyzer.heuristicDiagnosis(for: metrics(chlorosis: 0.05, necrosis: 0.20)).diseaseID, "general.leaf_spot")
        XCTAssertEqual(LeafPixelAnalyzer.heuristicDiagnosis(for: metrics(chlorosis: 0.25, necrosis: 0.02)).diseaseID, "general.chlorosis")
        XCTAssertLessThanOrEqual(LeafPixelAnalyzer.heuristicDiagnosis(for: metrics(chlorosis: 0.0, necrosis: 0.9)).confidence, 0.85,
                                 "heuristics never claim high certainty")
    }
}

final class LeafDiagnosisServiceTests: XCTestCase {

    private func service(classifier: LeafClassifying?) -> LeafDiagnosisService {
        LeafDiagnosisService(catalog: .shared, classifier: classifier, segmentationEnabled: false)
    }

    func testFallsBackToColourAnalysisWithoutModel() async throws {
        let result = try await service(classifier: nil).diagnose(TestImages.leaf(brownSpots: 6))
        XCTAssertEqual(result.engine, .colourAnalysis)
        XCTAssertEqual(result.diseaseID, "general.leaf_spot")
        XCTAssertLessThan(result.healthScore, 92)
        XCTAssertNotNil(DiseaseCatalog.shared.disease(id: result.diseaseID), "heuristic ids must exist in the catalogue")
    }

    func testHealthyLeafScoresHigh() async throws {
        let result = try await service(classifier: nil).diagnose(TestImages.leaf())
        XCTAssertEqual(result.diseaseID, "general.healthy")
        XCTAssertGreaterThanOrEqual(result.healthScore, 92)
        XCTAssertEqual(result.severity, .healthy)
    }

    func testModelPredictionsAreMappedToCatalogue() async throws {
        let classifier = MockClassifier(scores: [
            LabelScore(label: "Tomato___Early_blight", confidence: 0.82),
            LabelScore(label: "Tomato___Target_Spot", confidence: 0.10),
            LabelScore(label: "Unknown_label", confidence: 0.05)
        ])
        let result = try await service(classifier: classifier).diagnose(TestImages.leaf(brownSpots: 6))
        XCTAssertEqual(result.engine, .coreML)
        XCTAssertEqual(result.diseaseID, "tomato.early_blight")
        XCTAssertEqual(result.confidence, 0.82, accuracy: 0.0001)
        XCTAssertEqual(result.predictions.map(\.diseaseID), ["tomato.early_blight", "tomato.target_spot"], "unknown labels are dropped")
        XCTAssertFalse(result.warnings.contains(.lowConfidence))
    }

    func testLowConfidenceIsFlagged() async throws {
        let classifier = MockClassifier(scores: [LabelScore(label: "Potato___Late_blight", confidence: 0.31)])
        let result = try await service(classifier: classifier).diagnose(TestImages.leaf(brownSpots: 3))
        XCTAssertTrue(result.warnings.contains(.lowConfidence))
    }

    func testClassifierFailureFallsBackGracefully() async throws {
        let classifier = MockClassifier(scores: [], error: TestError())
        let result = try await service(classifier: classifier).diagnose(TestImages.leaf(yellowPatches: 6))
        XCTAssertEqual(result.engine, .colourAnalysis)
        XCTAssertEqual(result.diseaseID, "general.chlorosis")
    }

    func testPhotoQualityWarnings() async throws {
        let noLeaf = try await service(classifier: nil).diagnose(TestImages.solid(1, 1, 1))
        XCTAssertTrue(noLeaf.warnings.contains(.noLeafDetected))
        XCTAssertTrue(noLeaf.warnings.contains(.tooBright))

        let dark = try await service(classifier: nil).diagnose(TestImages.solid(0.05, 0.05, 0.05))
        XCTAssertTrue(dark.warnings.contains(.tooDark))
    }

    func testRejectsTinyImages() async {
        do {
            _ = try await service(classifier: nil).diagnose(TestImages.solid(0.2, 0.5, 0.2, size: 8))
            XCTFail("Expected unreadableImage")
        } catch {
            XCTAssertTrue(error is DiagnosisError)
        }
    }

    func testBundledSampleLeavesAreDiagnosedAsExpected() async throws {
        // Sample images live in the app's asset catalogue; unit tests are hosted in the app.
        for (name, expected) in [("SampleLeafHealthy", "general.healthy"),
                                 ("SampleLeafSpotted", "general.leaf_spot"),
                                 ("SampleLeafYellowing", "general.chlorosis")] {
            let image = try XCTUnwrap(UIImage(named: name)?.cgImage, "\(name) missing from asset catalogue")
            let result = try await service(classifier: nil).diagnose(image)
            XCTAssertEqual(result.diseaseID, expected, name)
        }
    }
}
