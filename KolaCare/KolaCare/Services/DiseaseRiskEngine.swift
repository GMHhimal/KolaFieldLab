//
//  DiseaseRiskEngine.swift
//  KolaCare
//
//  Turns an hourly weather forecast into an early-warning disease risk for the
//  crops a user grows. Most leaf diseases need a run of warm, wet hours to infect;
//  counting those "favourable hours" is the same principle used by classic
//  forecasting rules such as the Smith Period for potato late blight.
//

import SwiftUI

enum RiskLevel: Int, Comparable, CaseIterable, Sendable {
    case low = 0, moderate, high

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .low: "Low"
        case .moderate: "Moderate"
        case .high: "High"
        }
    }

    var color: Color {
        switch self {
        case .low: .green
        case .moderate: .orange
        case .high: .red
        }
    }
}

struct DiseaseRisk: Identifiable, Equatable, Sendable {
    let disease: Disease
    let level: RiskLevel
    let favourableHours: Int
    let windowHours: Int
    var id: String { disease.id }
}

struct DiseaseRiskEngine: Sendable {
    /// How far ahead to look.
    var windowHours = 48
    /// Rain (mm/h) that counts as leaf wetness on its own.
    var wetRainThreshold = 0.2

    func isFavourable(_ hour: WeatherForecast.Hour, for profile: RiskProfile) -> Bool {
        guard hour.temperature >= profile.minTemp, hour.temperature <= profile.maxTemp else { return false }
        let raining = hour.precipitation >= wetRainThreshold
        if let minHumidity = profile.minHumidity, !(hour.humidity >= minHumidity || raining) { return false }
        if let maxHumidity = profile.maxHumidity, !(hour.humidity <= maxHumidity && !raining) { return false }
        return true
    }

    func favourableHours(for profile: RiskProfile, in hours: [WeatherForecast.Hour]) -> Int {
        hours.reduce(0) { $0 + (isFavourable($1, for: profile) ? 1 : 0) }
    }

    func level(favourableHours: Int, profile: RiskProfile) -> RiskLevel {
        let ratio = Double(favourableHours) / Double(max(profile.hoursForHighRisk, 1))
        switch ratio {
        case 1...: return .high
        case 0.5..<1: return .moderate
        default: return .low
        }
    }

    /// Risks sorted from most to least urgent.
    func assess(_ forecast: WeatherForecast, diseases: [Disease], now: Date = .now) -> [DiseaseRisk] {
        let window = forecast.upcoming(hours: windowHours, from: now)
        return diseases.compactMap { disease -> DiseaseRisk? in
            guard let profile = disease.riskProfile else { return nil }
            let hours = favourableHours(for: profile, in: window)
            return DiseaseRisk(disease: disease,
                               level: level(favourableHours: hours, profile: profile),
                               favourableHours: hours,
                               windowHours: windowHours)
        }
        .sorted {
            if $0.level != $1.level { return $0.level > $1.level }
            return $0.favourableHours > $1.favourableHours
        }
    }

    /// Number of "wet" hours (humidity ≥ 90 % or rain) in the window — shown on the dashboard.
    func wetHours(in forecast: WeatherForecast, now: Date = .now) -> Int {
        forecast.upcoming(hours: windowHours, from: now)
            .filter { $0.humidity >= 90 || $0.precipitation >= wetRainThreshold }
            .count
    }
}
