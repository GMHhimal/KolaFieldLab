//
//  LocationProvider.swift
//  KolaCare
//
//  One-shot location lookups wrapped in async/await. Used to tag plants with
//  their field position and to fetch local weather. KolaCare only asks for
//  "When In Use" permission and never tracks location in the background.
//

import CoreLocation
import Observation

@MainActor
@Observable
final class LocationProvider: NSObject {
    /// Used when permission is denied: Colombo, Sri Lanka.
    static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 6.9271, longitude: 79.8612)

    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastLocation: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var continuations: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var canRequestPermission: Bool { authorizationStatus == .notDetermined }

    func requestPermission() {
        if canRequestPermission { manager.requestWhenInUseAuthorization() }
    }

    /// Returns the current location, or `nil` if unavailable / not permitted.
    func currentLocation() async -> CLLocation? {
        if let lastLocation, abs(lastLocation.timestamp.timeIntervalSinceNow) < 300 { return lastLocation }
        if canRequestPermission { requestPermission() }
        guard isAuthorized || canRequestPermission else { return nil }
        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
            if isAuthorized { manager.requestLocation() }
        }
    }

    /// Best available coordinate for weather lookups.
    func coordinateForWeather() async -> CLLocationCoordinate2D {
        await currentLocation()?.coordinate ?? Self.fallbackCoordinate
    }

    private func resume(with location: CLLocation?) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: location) }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if self.isAuthorized {
                if !self.continuations.isEmpty { self.manager.requestLocation() }
            } else if status != .notDetermined {
                self.resume(with: nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in
            self.lastLocation = location
            self.resume(with: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.resume(with: nil) }
    }
}
