//
//  ScanViewModel.swift
//  KolaCare
//
//  Drives the scan flow: image intake → analysis (off the main thread) → result → save.
//

import Foundation
import Observation
import OSLog
import SwiftData
import UIKit

@MainActor
@Observable
final class ScanViewModel {
    enum Phase: Equatable {
        case idle
        case analyzing
        case result
        case failed(String)
    }

    /// Stages shown while analysing — they mirror the real pipeline.
    static let analysisSteps: [LocalizedStringResource] = [
        "Isolating the leaf…",
        "Measuring yellow and dead tissue…",
        "Matching disease patterns…"
    ]

    private(set) var phase: Phase = .idle
    private(set) var image: UIImage?
    private(set) var result: DiagnosisResult?
    private(set) var analysisStep = 0
    private(set) var savedRecord: ScanRecord?

    @ObservationIgnored private let diagnoser: LeafDiagnosing
    @ObservationIgnored private let minimumAnalysisDuration: Duration
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var preparedImage: CGImage?

    init(diagnoser: LeafDiagnosing = LeafDiagnosisService.shared,
         minimumAnalysisDuration: Duration = .milliseconds(1600)) {
        self.diagnoser = diagnoser
        self.minimumAnalysisDuration = minimumAnalysisDuration
    }

    var isAnalyzing: Bool { phase == .analyzing }

    // MARK: Intake

    func analyze(imageData: Data) {
        guard let cgImage = ImageProcessing.downsample(imageData, maxPixelSize: ImageProcessing.analysisMaxPixel) else {
            phase = .failed(DiagnosisError.unreadableImage.localizedDescription)
            return
        }
        analyze(cgImage: cgImage)
    }

    func analyze(uiImage: UIImage) {
        guard let data = uiImage.jpegData(compressionQuality: 0.9) else {
            phase = .failed(DiagnosisError.unreadableImage.localizedDescription)
            return
        }
        analyze(imageData: data)
    }

    func analyze(cgImage: CGImage) {
        analysisTask?.cancel()
        preparedImage = cgImage
        image = UIImage(cgImage: cgImage)
        result = nil
        savedRecord = nil
        analysisStep = 0
        phase = .analyzing

        let diagnoser = self.diagnoser
        let minimum = minimumAnalysisDuration
        analysisTask = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            // Advance the visible pipeline steps while the real work runs.
            let stepper = Task { @MainActor [weak self] in
                for step in 1..<Self.analysisSteps.count {
                    try? await Task.sleep(for: minimum / Self.analysisSteps.count)
                    guard !Task.isCancelled else { return }
                    self?.analysisStep = step
                }
            }
            do {
                let diagnosis = try await Task.detached(priority: .userInitiated) {
                    try await diagnoser.diagnose(cgImage)
                }.value
                let elapsed = clock.now - start
                if elapsed < minimum { try? await Task.sleep(for: minimum - elapsed) }
                stepper.cancel()
                guard !Task.isCancelled else { return }
                self?.finish(with: diagnosis)
            } catch {
                stepper.cancel()
                guard !Task.isCancelled else { return }
                Logger.diagnosis.error("Diagnosis failed: \(error.localizedDescription, privacy: .public)")
                self?.phase = .failed(error.localizedDescription)
            }
        }
    }

    private func finish(with diagnosis: DiagnosisResult) {
        result = diagnosis
        analysisStep = Self.analysisSteps.count - 1
        phase = .result
    }

    /// Awaits the in-flight analysis (used by unit tests).
    func waitForAnalysis() async {
        await analysisTask?.value
    }

    func reset() {
        analysisTask?.cancel()
        analysisTask = nil
        phase = .idle
        image = nil
        result = nil
        preparedImage = nil
        savedRecord = nil
        analysisStep = 0
    }

    // MARK: Save

    /// Persists the diagnosis to a plant and optionally schedules a follow-up reminder.
    @discardableResult
    func save(to plant: Plant, notes: String, followUpInDays: Int?, context: ModelContext, now: Date = .now) -> ScanRecord? {
        guard let result, let preparedImage else { return nil }
        let images = ImageProcessing.prepareForStorage(preparedImage)
        let followUp = followUpInDays.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: now) }
            .map { Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: $0) ?? $0 }
        let record = GardenRepository(context: context).addScan(to: plant, result: result,
                                                                photo: images.photo, thumbnail: images.thumbnail,
                                                                notes: notes, followUpDate: followUp, date: now)
        if let followUp {
            let scanID = record.id, plantID = plant.id, name = plant.name
            Task { await NotificationService.shared.scheduleFollowUp(scanID: scanID, plantID: plantID, plantName: name, at: followUp) }
        }
        savedRecord = record
        return record
    }
}
