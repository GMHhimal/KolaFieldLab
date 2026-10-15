//
//  WeatherForecast.swift
//  KolaCare
//
//  App-level weather model, decoupled from the Open-Meteo wire format.
//

import Foundation

struct WeatherForecast: Codable, Equatable, Sendable {
    struct Current: Codable, Equatable, Sendable {
        let temperature: Double
        let humidity: Double
        let precipitation: Double
        let weatherCode: Int
    }

    struct Hour: Codable, Equatable, Sendable {
        let date: Date
        let temperature: Double
        let humidity: Double
        let precipitation: Double
    }

    let latitude: Double
    let longitude: Double
    let current: Current
    let hourly: [Hour]
    let fetchedAt: Date

    func isFresh(maxAge: TimeInterval = 60 * 60, now: Date = .now) -> Bool {
        now.timeIntervalSince(fetchedAt) < maxAge
    }

    /// Hours from `now` up to `window` hours ahead.
    func upcoming(hours window: Int, from now: Date = .now) -> [Hour] {
        let end = now.addingTimeInterval(TimeInterval(window) * 3600)
        let startOfHour = now.addingTimeInterval(-3599)
        return hourly.filter { $0.date >= startOfHour && $0.date < end }
    }
}

/// WMO weather interpretation codes used by Open-Meteo.
enum WeatherCondition {
    static func symbol(for code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(for code: Int) -> LocalizedStringResource {
        switch code {
        case 0: "Clear sky"
        case 1, 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorm"
        default: "Cloudy"
        }
    }
}
