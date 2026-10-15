//
//  WeatherService.swift
//  KolaCare
//
//  Networking layer: fetches an hourly forecast from Open-Meteo (free, no API key,
//  CC BY 4.0 — attribution shown in Settings › About) and caches it on disk so the
//  disease-risk card keeps working offline in the field.
//

import Foundation
import OSLog

protocol WeatherProviding: Sendable {
    func forecast(latitude: Double, longitude: Double) async throws -> WeatherForecast
}

enum WeatherError: LocalizedError, Equatable {
    case badStatus(Int)
    case invalidResponse
    case decoding

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): String(localized: "Weather service returned an error (\(code)).")
        case .invalidResponse: String(localized: "Unexpected response from the weather service.")
        case .decoding: String(localized: "Couldn't read the weather data.")
        }
    }
}

struct OpenMeteoWeatherService: WeatherProviding {
    static let baseURL = URL(string: "https://api.open-meteo.com/v1/forecast")!

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    static func requestURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,precipitation,weather_code"),
            URLQueryItem(name: "hourly", value: "temperature_2m,relative_humidity_2m,precipitation"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        return components.url!
    }

    func forecast(latitude: Double, longitude: Double) async throws -> WeatherForecast {
        var request = URLRequest(url: Self.requestURL(latitude: latitude, longitude: longitude))
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WeatherError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw WeatherError.badStatus(http.statusCode) }
        do {
            return try OpenMeteoResponse.decode(data).toForecast(fetchedAt: .now)
        } catch {
            Logger.network.error("Weather decoding failed: \(error.localizedDescription, privacy: .public)")
            throw WeatherError.decoding
        }
    }
}

// MARK: - Wire format

struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double
        let humidity: Double
        let precipitation: Double?
        let weatherCode: Int?

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case humidity = "relative_humidity_2m"
            case precipitation
            case weatherCode = "weather_code"
        }
    }

    struct Hourly: Decodable {
        let time: [String]
        let temperature: [Double?]
        let humidity: [Double?]
        let precipitation: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature = "temperature_2m"
            case humidity = "relative_humidity_2m"
            case precipitation
        }
    }

    let latitude: Double
    let longitude: Double
    let utcOffsetSeconds: Int
    let current: Current
    let hourly: Hourly

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, current, hourly
        case utcOffsetSeconds = "utc_offset_seconds"
    }

    static func decode(_ data: Data) throws -> OpenMeteoResponse {
        try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
    }

    /// Open-Meteo returns local times without a zone ("2026-10-13T18:00"), so the
    /// response's UTC offset is applied while parsing.
    func toForecast(fetchedAt: Date) -> WeatherForecast {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .gmt

        let count = [hourly.time.count, hourly.temperature.count, hourly.humidity.count, hourly.precipitation.count].min() ?? 0
        var hours: [WeatherForecast.Hour] = []
        hours.reserveCapacity(count)
        for index in 0..<count {
            guard let date = formatter.date(from: hourly.time[index]),
                  let temperature = hourly.temperature[index],
                  let humidity = hourly.humidity[index] else { continue }
            hours.append(.init(date: date,
                               temperature: temperature,
                               humidity: humidity,
                               precipitation: hourly.precipitation[index] ?? 0))
        }

        return WeatherForecast(
            latitude: latitude,
            longitude: longitude,
            current: .init(temperature: current.temperature,
                           humidity: current.humidity,
                           precipitation: current.precipitation ?? 0,
                           weatherCode: current.weatherCode ?? 3),
            hourly: hours,
            fetchedAt: fetchedAt)
    }
}

// MARK: - Offline cache

/// Small JSON file cache in Application Support. Weather is not user data,
/// so it lives outside SwiftData and is safe to delete at any time.
struct WeatherCache: Sendable {
    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.fileURL = folder.appendingPathComponent("weather-cache.json")
        }
    }

    func load() -> WeatherForecast? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WeatherForecast.self, from: data)
    }

    func save(_ forecast: WeatherForecast) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(forecast) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
