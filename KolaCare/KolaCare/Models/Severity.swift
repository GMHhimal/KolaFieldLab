//
//  Severity.swift
//  KolaCare
//
//  Disease severity graded from the share of leaf area showing symptoms,
//  the same idea agronomists use with visual severity scales.
//

import SwiftUI

enum Severity: Int, CaseIterable, Comparable, Codable, Sendable {
    case healthy = 0, low, moderate, severe

    /// - Parameters:
    ///   - affectedArea: fraction (0…1) of leaf tissue that is yellow or dead.
    ///   - isHealthyDiagnosis: a confident "healthy" diagnosis caps severity at `.low`.
    init(affectedArea: Double, isHealthyDiagnosis: Bool = false) {
        let value: Severity
        switch affectedArea {
        case ..<0.05: value = .healthy
        case ..<0.15: value = .low
        case ..<0.35: value = .moderate
        default: value = .severe
        }
        self = isHealthyDiagnosis ? min(value, .low) : value
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .healthy: "Healthy"
        case .low: "Low"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }

    var color: Color {
        switch self {
        case .healthy: .green
        case .low: .yellow
        case .moderate: .orange
        case .severe: .red
        }
    }

    var symbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .low: "exclamationmark.circle.fill"
        case .moderate: "exclamationmark.triangle.fill"
        case .severe: "flame.fill"
        }
    }
}

enum HealthScore {
    /// Converts the affected leaf area into a 0–100 score shown in health rings.
    /// 0 % affected → 100, ~62 % or more affected → 0.
    static func from(affectedArea: Double) -> Int {
        let clamped = min(max(affectedArea, 0), 1)
        return max(0, Int(((1 - min(1, clamped * 1.6)) * 100).rounded()))
    }

    static func severity(for score: Int) -> Severity {
        switch score {
        case 92...: .healthy
        case 76..<92: .low
        case 44..<76: .moderate
        default: .severe
        }
    }
}
