//
//  Plant.swift
//  KolaCare
//
//  SwiftData entity for a plant, bed or plot the user monitors.
//

import Foundation
import SwiftData
import CoreLocation

@Model
final class Plant {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Stored as a raw string so it can be used in predicates and survives enum changes.
    var cropRaw: String
    var plotName: String
    var notes: String
    var plantedOn: Date?
    var createdAt: Date
    var latitude: Double?
    var longitude: Double?
    /// Large binary data lives outside the SQLite store.
    @Attribute(.externalStorage) var photoData: Data?

    @Relationship(deleteRule: .cascade, inverse: \ScanRecord.plant)
    var scans: [ScanRecord] = []

    init(id: UUID = UUID(),
         name: String,
         crop: Crop,
         plotName: String = "",
         notes: String = "",
         plantedOn: Date? = nil,
         createdAt: Date = .now,
         coordinate: CLLocationCoordinate2D? = nil,
         photoData: Data? = nil) {
        self.id = id
        self.name = name
        self.cropRaw = crop.rawValue
        self.plotName = plotName
        self.notes = notes
        self.plantedOn = plantedOn
        self.createdAt = createdAt
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.photoData = photoData
    }

    // MARK: - Derived values (not persisted)

    var crop: Crop {
        get { Crop(rawValue: cropRaw) ?? .other }
        set { cropRaw = newValue.rawValue }
    }

    var coordinate: CLLocationCoordinate2D? {
        get {
            guard let latitude, let longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        set {
            latitude = newValue?.latitude
            longitude = newValue?.longitude
        }
    }

    /// Newest first.
    var sortedScans: [ScanRecord] { scans.sorted { $0.date > $1.date } }

    var latestScan: ScanRecord? { scans.max(by: { $0.date < $1.date }) }

    /// `nil` until the plant has been scanned at least once.
    var healthScore: Int? { latestScan?.healthScore }

    var severity: Severity? { healthScore.map(HealthScore.severity(for:)) }

    /// Thumbnail used in lists: the plant photo, otherwise the latest scan.
    var displayImageData: Data? { photoData ?? latestScan?.thumbnailData }
}
