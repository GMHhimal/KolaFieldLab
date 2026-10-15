//
//  ScanRecord.swift
//  KolaCare
//
//  SwiftData entity storing one leaf diagnosis and the treatment progress for it.
//

import Foundation
import SwiftData

@Model
final class ScanRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    @Attribute(.externalStorage) var imageData: Data?
    /// Small JPEG (≈300 px) kept inline for fast list rendering.
    var thumbnailData: Data?
    var diseaseID: String
    var confidence: Double
    /// Fraction (0…1) of the leaf showing yellowing or dead tissue.
    var affectedArea: Double
    var chlorosisFraction: Double
    var necrosisFraction: Double
    var healthScore: Int
    var engineRaw: String
    var notes: String
    /// Indices into `Disease.treatmentPlan` the user has ticked off.
    var completedSteps: [Int]
    var followUpDate: Date?
    var plant: Plant?

    init(id: UUID = UUID(),
         date: Date = .now,
         imageData: Data? = nil,
         thumbnailData: Data? = nil,
         diseaseID: String,
         confidence: Double,
         affectedArea: Double,
         chlorosisFraction: Double = 0,
         necrosisFraction: Double = 0,
         healthScore: Int,
         engine: DiagnosisEngine,
         notes: String = "",
         completedSteps: [Int] = [],
         followUpDate: Date? = nil) {
        self.id = id
        self.date = date
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.diseaseID = diseaseID
        self.confidence = confidence
        self.affectedArea = affectedArea
        self.chlorosisFraction = chlorosisFraction
        self.necrosisFraction = necrosisFraction
        self.healthScore = healthScore
        self.engineRaw = engine.rawValue
        self.notes = notes
        self.completedSteps = completedSteps
        self.followUpDate = followUpDate
    }

    var engine: DiagnosisEngine { DiagnosisEngine(rawValue: engineRaw) ?? .colourAnalysis }

    var severity: Severity { HealthScore.severity(for: healthScore) }

    func toggleStep(_ index: Int) {
        if let position = completedSteps.firstIndex(of: index) {
            completedSteps.remove(at: position)
        } else {
            completedSteps.append(index)
        }
    }

    func isStepDone(_ index: Int) -> Bool { completedSteps.contains(index) }

    /// 0…1 progress through the treatment plan.
    func treatmentProgress(totalSteps: Int) -> Double {
        guard totalSteps > 0 else { return 1 }
        return Double(Set(completedSteps).filter { $0 < totalSteps }.count) / Double(totalSteps)
    }
}
