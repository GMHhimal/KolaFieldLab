//
//  DiagnosisResult.swift
//  KolaCare
//
//  Output of the on-device diagnosis pipeline.
//

import CoreGraphics
import SwiftUI

enum DiagnosisEngine: String, Codable, Sendable {
    /// Custom image classifier trained with Create ML and run through Vision.
    case coreML
    /// Pixel-level colour analysis fallback (works with no model, e.g. in the Simulator).
    case colourAnalysis

    var title: LocalizedStringResource {
        switch self {
        case .coreML: "CoreML disease model"
        case .colourAnalysis: "On-device colour analysis"
        }
    }

    var symbol: String {
        switch self {
        case .coreML: "cpu"
        case .colourAnalysis: "eyedropper.halffull"
        }
    }
}

/// Measured composition of the leaf.
struct LeafMetrics: Equatable, Sendable {
    /// Share of the analysed image covered by leaf tissue.
    var leafCoverage: Double
    var greenFraction: Double
    /// Share of leaf tissue that is yellow.
    var chlorosisFraction: Double
    /// Share of leaf tissue that is brown/black (dead).
    var necrosisFraction: Double
    /// 0…1 average brightness of the photo.
    var meanLuminance: Double
    /// `true` when Vision isolated the leaf from the background first.
    var usedSegmentation: Bool

    var affectedArea: Double { min(1, chlorosisFraction + necrosisFraction) }

    static let empty = LeafMetrics(leafCoverage: 0, greenFraction: 0, chlorosisFraction: 0,
                                   necrosisFraction: 0, meanLuminance: 0, usedSegmentation: false)
}

/// A single ranked prediction mapped to a catalogue entry.
struct Prediction: Identifiable, Equatable, Sendable {
    let diseaseID: String
    let confidence: Double
    var id: String { diseaseID }
}

enum QualityWarning: String, CaseIterable, Sendable {
    case noLeafDetected, tooDark, tooBright, lowConfidence

    var message: LocalizedStringResource {
        switch self {
        case .noLeafDetected: "We couldn't find much leaf in this photo. Fill the frame with a single leaf."
        case .tooDark: "The photo is quite dark. Try again in daylight or shade, not at night."
        case .tooBright: "The photo is over-exposed. Avoid direct midday sun on the leaf."
        case .lowConfidence: "The model isn't sure. Retake the photo or compare with the Library."
        }
    }

    var symbol: String {
        switch self {
        case .noLeafDetected: "viewfinder"
        case .tooDark: "moon.fill"
        case .tooBright: "sun.max.fill"
        case .lowConfidence: "questionmark.circle"
        }
    }
}

struct DiagnosisResult: @unchecked Sendable {
    let diseaseID: String
    let confidence: Double
    /// Top predictions (up to 3). For colour analysis this contains the single heuristic result.
    let predictions: [Prediction]
    let metrics: LeafMetrics
    let engine: DiagnosisEngine
    let warnings: [QualityWarning]
    /// Semi-transparent overlay highlighting yellow (amber) and dead (red) tissue, same aspect as the photo.
    let lesionMap: CGImage?

    var healthScore: Int {
        let score = HealthScore.from(affectedArea: metrics.affectedArea)
        // A confident "healthy" model result should not be dragged down by background noise.
        return diseaseID.hasSuffix("healthy") ? max(score, 92) : score
    }

    /// Derived from the health score so the result screen and saved records always agree.
    var severity: Severity { HealthScore.severity(for: healthScore) }
}
