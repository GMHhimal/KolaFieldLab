//
//  WeatherServiceTests.swift
//  KolaCareTests
//
//  Networking layer tested against canned HTTP responses (no real network).
//

import XCTest
@testable import KolaCare

final class WeatherServiceTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    private func respond(status: Int, body: Data) {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, body)
        }
    }

    func testDecodesOpenMeteoForecast() async throws {
        respond(status: 200, body: Fixtures.openMeteoJSON(hours: 6, humidity: 95, temperature: 22))
        let service = OpenMeteoWeatherService(session: MockURLProtocol.session())

        let forecast = try await service.forecast(latitude: 7.87, longitude: 80.65)

        XCTAssertEqual(forecast.hourly.count, 6)
        XCTAssertEqual(forecast.current.humidity, 95)
        XCTAssertEqual(forecast.current.temperature, 22)
        XCTAssertEqual(forecast.current.weatherCode, 61)
        // "2026-10-13T00:00" at UTC+05:30 is 2026-10-12 18:30 UTC.
        let expected = ISO8601DateFormatter().date(from: "2026-10-12T18:30:00Z")
        XCTAssertEqual(forecast.hourly.first?.date, expected)
        XCTAssertEqual(forecast.hourly[1].date.timeIntervalSince(forecast.hourly[0].date), 3600)
    }

    func testRequestAsksForTheFieldsTheRiskEngineNeeds() async throws {
        respond(status: 200, body: Fixtures.openMeteoJSON())
        _ = try await OpenMeteoWeatherService(session: MockURLProtocol.session()).forecast(latitude: 6.9271, longitude: 79.8612)

        let url = try XCTUnwrap(MockURLProtocol.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.hasPrefix("https://api.open-meteo.com/v1/forecast"))
        XCTAssertTrue(url.contains("latitude=6.9271"))
        XCTAssertTrue(url.contains("relative_humidity_2m"))
        XCTAssertTrue(url.contains("precipitation"))
        XCTAssertTrue(url.contains("timezone=auto"))
    }

    func testServerErrorIsReported() async {
        respond(status: 503, body: Data())
        do {
            _ = try await OpenMeteoWeatherService(session: MockURLProtocol.session()).forecast(latitude: 0, longitude: 0)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? WeatherError, .badStatus(503))
        }
    }

    func testMalformedJSONIsReported() async {
        respond(status: 200, body: Data("{\"unexpected\": true}".utf8))
        do {
            _ = try await OpenMeteoWeatherService(session: MockURLProtocol.session()).forecast(latitude: 0, longitude: 0)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? WeatherError, .decoding)
        }
    }

    func testNullHourlyValuesAreSkipped() throws {
        let json = """
        {"latitude": 7, "longitude": 80, "utc_offset_seconds": 0,
         "current": {"temperature_2m": 25, "relative_humidity_2m": 80},
         "hourly": {"time": ["2026-10-13T00:00", "2026-10-13T01:00"],
                    "temperature_2m": [25, null], "relative_humidity_2m": [80, 81], "precipitation": [0, 0]}}
        """
        let forecast = try OpenMeteoResponse.decode(Data(json.utf8)).toForecast(fetchedAt: .now)
        XCTAssertEqual(forecast.hourly.count, 1)
        XCTAssertEqual(forecast.current.weatherCode, 3, "missing weather code falls back to overcast")
    }

    func testCacheRoundTripAndFreshness() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("weather-\(UUID().uuidString).json")
        let cache = WeatherCache(fileURL: url)
        defer { cache.clear() }

        let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)
        let forecast = Fixtures.forecast(hours: [(temperature: 24.0, humidity: 91.0, rain: 0.0)], start: fetchedAt)
        cache.save(forecast)

        let loaded = try XCTUnwrap(cache.load())
        XCTAssertEqual(loaded.hourly.count, 1)
        XCTAssertEqual(loaded.fetchedAt.timeIntervalSince1970, fetchedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(loaded.isFresh(now: fetchedAt.addingTimeInterval(30 * 60)))
        XCTAssertFalse(loaded.isFresh(now: fetchedAt.addingTimeInterval(2 * 60 * 60)))
    }

    @MainActor
    func testDashboardFallsBackToCacheWhenOffline() async throws {
        struct OfflineService: WeatherProviding {
            func forecast(latitude: Double, longitude: Double) async throws -> WeatherForecast { throw URLError(.notConnectedToInternet) }
        }
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("weather-\(UUID().uuidString).json")
        let cache = WeatherCache(fileURL: url)
        defer { cache.clear() }
        // A stale (3 h old) but usable cached forecast.
        cache.save(Fixtures.forecast(hours: Array(repeating: (temperature: 18.0, humidity: 95.0, rain: 0.0), count: 60),
                                     start: now.addingTimeInterval(-3 * 3600)))

        let viewModel = DashboardViewModel(weatherService: OfflineService(), cache: cache)
        await viewModel.load(crops: [.potato], coordinate: { LocationProvider.fallbackCoordinate }, now: now)

        XCTAssertNotNil(viewModel.forecast)
        XCTAssertTrue(viewModel.isShowingCachedData)
        XCTAssertFalse(viewModel.risks.isEmpty, "risks are still computed from the cached forecast")
        if case .failed = viewModel.state {} else { XCTFail("state should report the network failure") }
    }
}
