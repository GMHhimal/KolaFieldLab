//
//  GardenRepository.swift
//  KolaCare
//
//  Write operations on the garden, kept out of the views so they can be unit
//  tested against an in-memory ModelContainer. Views read with @Query.
//

import Foundation
import SwiftData
import OSLog

@MainActor
struct GardenRepository {
    let context: ModelContext

    @discardableResult
    func addPlant(name: String, crop: Crop, plotName: String = "", notes: String = "",
                  plantedOn: Date? = nil, latitude: Double? = nil, longitude: Double? = nil,
                  photoData: Data? = nil) -> Plant {
        let plant = Plant(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                          crop: crop, plotName: plotName, notes: notes, plantedOn: plantedOn,
                          photoData: photoData)
        plant.latitude = latitude
        plant.longitude = longitude
        context.insert(plant)
        save()
        return plant
    }

    @discardableResult
    func addScan(to plant: Plant, result: DiagnosisResult, photo: Data?, thumbnail: Data?,
                 notes: String = "", followUpDate: Date? = nil, date: Date = .now) -> ScanRecord {
        let record = ScanRecord(date: date,
                                imageData: photo,
                                thumbnailData: thumbnail,
                                diseaseID: result.diseaseID,
                                confidence: result.confidence,
                                affectedArea: result.metrics.affectedArea,
                                chlorosisFraction: result.metrics.chlorosisFraction,
                                necrosisFraction: result.metrics.necrosisFraction,
                                healthScore: result.healthScore,
                                engine: result.engine,
                                notes: notes,
                                followUpDate: followUpDate)
        context.insert(record)
        record.plant = plant
        save()
        return record
    }

    func delete(_ plant: Plant) {
        NotificationService.shared.cancelFollowUps(scanIDs: plant.scans.map(\.id))
        context.delete(plant)
        save()
    }

    func delete(_ scan: ScanRecord) {
        NotificationService.shared.cancelFollowUps(scanIDs: [scan.id])
        context.delete(scan)
        save()
    }

    func plant(withID id: UUID) -> Plant? {
        var descriptor = FetchDescriptor<Plant>(predicate: #Predicate<Plant> { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func allPlants() -> [Plant] {
        (try? context.fetch(FetchDescriptor<Plant>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    func eraseAll() {
        // Deleting through the context (rather than a batch delete) keeps @Query
        // views in sync and lets the cascade rule remove each plant's scans.
        let plants = allPlants()
        NotificationService.shared.cancelFollowUps(scanIDs: plants.flatMap { $0.scans.map(\.id) })
        plants.forEach { context.delete($0) }
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Logger.persistence.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - CSV export

enum GardenCSVExporter {
    static let header = "plant,crop,plot,scan_date,diagnosis,confidence,health_score,affected_area_percent,engine,notes"

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    static func csv(for plants: [Plant], catalog: DiseaseCatalog) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = [header]
        for plant in plants.sorted(by: { $0.name < $1.name }) {
            for scan in plant.sortedScans {
                let diagnosis = catalog.disease(id: scan.diseaseID)?.names.en ?? scan.diseaseID
                let row = [plant.name, plant.crop.rawValue, plant.plotName, formatter.string(from: scan.date), diagnosis,
                           String(format: "%.2f", scan.confidence), String(scan.healthScore),
                           String(format: "%.1f", scan.affectedArea * 100), scan.engineRaw, scan.notes]
                lines.append(row.map(escape).joined(separator: ","))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
