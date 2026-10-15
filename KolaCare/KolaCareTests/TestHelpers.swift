//
//  TestHelpers.swift
//  KolaCareTests
//
//  Synthetic images, mocks and fixtures shared by the unit tests.
//

import CoreGraphics
import Foundation
import SwiftData
@testable import KolaCare

enum TestImages {
    /// Draws a leaf-like ellipse on a light background, optionally with brown spots and yellow patches.
    static func leaf(size: Int = 400,
                     background: (CGFloat, CGFloat, CGFloat) = (0.93, 0.91, 0.84),
                     leaf: (CGFloat, CGFloat, CGFloat) = (0.20, 0.52, 0.22),
                     brownSpots: Int = 0,
                     yellowPatches: Int = 0) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let s = CGFloat(size)
        context.setFillColor(red: background.0, green: background.1, blue: background.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: s, height: s))

        let leafRect = CGRect(x: s * 0.2, y: s * 0.1, width: s * 0.6, height: s * 0.8)
        context.setFillColor(red: leaf.0, green: leaf.1, blue: leaf.2, alpha: 1)
        context.fillEllipse(in: leafRect)

        for index in 0..<yellowPatches {
            let x = leafRect.minX + leafRect.width * (0.25 + 0.5 * CGFloat(index % 2))
            let y = leafRect.minY + leafRect.height * (0.15 + 0.2 * CGFloat(index / 2 % 4))
            context.setFillColor(red: 0.86, green: 0.80, blue: 0.26, alpha: 1)
            context.fillEllipse(in: CGRect(x: x - s * 0.08, y: y - s * 0.06, width: s * 0.16, height: s * 0.12))
        }
        for index in 0..<brownSpots {
            let x = leafRect.minX + leafRect.width * (0.2 + 0.6 * CGFloat((index * 37) % 10) / 10)
            let y = leafRect.minY + leafRect.height * (0.15 + 0.7 * CGFloat((index * 53) % 10) / 10)
            context.setFillColor(red: 0.40, green: 0.25, blue: 0.11, alpha: 1)
            context.fillEllipse(in: CGRect(x: x - s * 0.05, y: y - s * 0.05, width: s * 0.10, height: s * 0.10))
        }
        return context.makeImage()!
    }

    static func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, size: Int = 64) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: r, green: g, blue: b, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }
}

/// Classifier stub returning fixed labels.
struct MockClassifier: LeafClassifying {
    var modelName = "MockModel"
    var scores: [LabelScore]
    var error: Error?

    func classify(_ image: CGImage) throws -> [LabelScore] {
        if let error { throw error }
        return scores
    }
}

/// Diagnoser stub for view-model tests.
struct MockDiagnoser: LeafDiagnosing {
    var result: DiagnosisResult?
    var error: Error?

    func diagnose(_ image: CGImage) async throws -> DiagnosisResult {
        if let error { throw error }
        return result!
    }

    static func sample(diseaseID: String = "tomato.early_blight", affected: Double = 0.2) -> DiagnosisResult {
        DiagnosisResult(diseaseID: diseaseID, confidence: 0.9,
                        predictions: [Prediction(diseaseID: diseaseID, confidence: 0.9)],
                        metrics: LeafMetrics(leafCoverage: 0.5, greenFraction: 1 - affected, chlorosisFraction: affected / 2,
                                             necrosisFraction: affected / 2, meanLuminance: 0.5, usedSegmentation: false),
                        engine: .coreML, warnings: [], lesionMap: nil)
    }
}

struct TestError: Error {}

/// Intercepts URLSession requests and returns canned responses.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

enum Fixtures {
    /// Trimmed real-shape Open-Meteo response (UTC+05:30, Sri Lanka).
    static func openMeteoJSON(hours: Int = 6, humidity: Double = 95, temperature: Double = 22, start: String = "2026-10-13T00:00") -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 19_800)
        let startDate = formatter.date(from: start)!
        let times = (0..<hours).map { "\"\(formatter.string(from: startDate.addingTimeInterval(Double($0) * 3600)))\"" }
        let temps = Array(repeating: "\(temperature)", count: hours)
        let hums = Array(repeating: "\(Int(humidity))", count: hours)
        let rain = Array(repeating: "0.0", count: hours)
        let json = """
        {
          "latitude": 7.875, "longitude": 80.625, "generationtime_ms": 0.1,
          "utc_offset_seconds": 19800, "timezone": "Asia/Colombo", "timezone_abbreviation": "GMT+5:30",
          "elevation": 160.0,
          "current_units": {"time": "iso8601", "temperature_2m": "°C"},
          "current": {"time": "\(start)", "interval": 900, "temperature_2m": \(temperature),
                      "relative_humidity_2m": \(Int(humidity)), "precipitation": 0.2, "weather_code": 61},
          "hourly_units": {"time": "iso8601"},
          "hourly": {"time": [\(times.joined(separator: ","))],
                     "temperature_2m": [\(temps.joined(separator: ","))],
                     "relative_humidity_2m": [\(hums.joined(separator: ","))],
                     "precipitation": [\(rain.joined(separator: ","))]}
        }
        """
        return Data(json.utf8)
    }

    static func forecast(hours: [(temperature: Double, humidity: Double, rain: Double)], start: Date) -> WeatherForecast {
        WeatherForecast(latitude: 7.87, longitude: 80.65,
                        current: .init(temperature: 25, humidity: 80, precipitation: 0, weatherCode: 2),
                        hourly: hours.enumerated().map { index, hour in
                            WeatherForecast.Hour(date: start.addingTimeInterval(Double(index) * 3600),
                                  temperature: hour.temperature, humidity: hour.humidity, precipitation: hour.rain)
                        },
                        fetchedAt: start)
    }

    /// Keep a reference to the returned container for the test's lifetime;
    /// its `mainContext` is only valid while the container is alive.
    @MainActor
    static func inMemoryContainer() -> ModelContainer {
        PersistenceController.makeContainer(inMemory: true)
    }
}
