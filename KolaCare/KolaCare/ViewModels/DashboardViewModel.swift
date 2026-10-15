//
//  DashboardViewModel.swift
//  KolaCare
//
//  Loads the local forecast (cache-first, network when stale) and computes
//  disease risks for the crops the user grows.
//

import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    private(set) var forecast: WeatherForecast?
    private(set) var risks: [DiseaseRisk] = []
    private(set) var wetHours = 0
    private(set) var state: LoadState = .idle
    /// True when showing cached data because the network request failed.
    private(set) var isShowingCachedData = false

    @ObservationIgnored private let weatherService: WeatherProviding
    @ObservationIgnored private let cache: WeatherCache
    @ObservationIgnored private let engine: DiseaseRiskEngine
    @ObservationIgnored private let catalog: DiseaseCatalog

    init(weatherService: WeatherProviding = OpenMeteoWeatherService(),
         cache: WeatherCache = WeatherCache(),
         engine: DiseaseRiskEngine = DiseaseRiskEngine(),
         catalog: DiseaseCatalog = .shared) {
        self.weatherService = weatherService
        self.cache = cache
        self.engine = engine
        self.catalog = catalog
    }

    var isLoading: Bool { state == .loading }

    /// Highest current risk, used for the headline banner.
    var topRisk: DiseaseRisk? { risks.first }

    func load(crops: Set<Crop>, coordinate: () async -> CLLocationCoordinate2D, force: Bool = false, now: Date = .now) async {
        if forecast == nil, let cached = cache.load() {
            apply(cached, crops: crops, now: now)
            isShowingCachedData = !cached.isFresh(now: now)
        }
        if !force, let forecast, forecast.isFresh(now: now) {
            state = .loaded
            return
        }

        state = .loading
        let location = await coordinate()
        do {
            let fresh = try await weatherService.forecast(latitude: location.latitude, longitude: location.longitude)
            cache.save(fresh)
            apply(fresh, crops: crops, now: now)
            isShowingCachedData = false
            state = .loaded
        } catch is CancellationError {
            state = forecast == nil ? .idle : .loaded
        } catch {
            isShowingCachedData = forecast != nil
            state = .failed(error.localizedDescription)
        }
    }

    /// Re-evaluates risks when the user's crops change, without hitting the network.
    func updateCrops(_ crops: Set<Crop>, now: Date = .now) {
        guard let forecast else { return }
        apply(forecast, crops: crops, now: now)
    }

    private func apply(_ forecast: WeatherForecast, crops: Set<Crop>, now: Date) {
        self.forecast = forecast
        let diseases = catalog.weatherSensitiveDiseases(for: crops)
        risks = engine.assess(forecast, diseases: diseases, now: now)
        wetHours = engine.wetHours(in: forecast, now: now)
    }
}
