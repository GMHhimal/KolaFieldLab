//
//  NotificationService.swift
//  KolaCare
//
//  Local "re-scan" reminders. Treatment only works if the farmer checks whether
//  it worked, so each saved diagnosis can schedule a follow-up. Tapping the
//  reminder deep-links to the plant.
//

import Foundation
import OSLog
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()
    static let plantIDKey = "plantID"

    /// Set by the UI layer; called on the main actor when a reminder is tapped.
    @MainActor var onOpenPlant: ((UUID) -> Void)?
    /// Holds a tap that arrived before the UI was ready (cold launch from a notification).
    @MainActor private(set) var pendingPlantID: UUID?

    private var center: UNUserNotificationCenter { .current() }

    func configure() {
        center.delegate = self
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Logger.notifications.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Schedules a reminder to re-scan a plant. Replaces any earlier reminder for the same scan.
    func scheduleFollowUp(scanID: UUID, plantID: UUID, plantName: String, at date: Date) async {
        guard await requestAuthorization() else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to check \(plantName)")
        content.body = String(localized: "Re-scan a leaf to see whether the treatment is working.")
        content.sound = .default
        content.userInfo = [Self.plantIDKey: plantID.uuidString]
        content.threadIdentifier = plantID.uuidString

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: scanID.uuidString, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            Logger.notifications.error("Scheduling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func cancelFollowUps(scanIDs: [UUID]) {
        center.removePendingNotificationRequests(withIdentifiers: scanIDs.map(\.uuidString))
    }

    @MainActor
    func consumePendingPlantID() -> UUID? {
        defer { pendingPlantID = nil }
        return pendingPlantID
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo[Self.plantIDKey] as? String,
              let plantID = UUID(uuidString: raw) else { return }
        await MainActor.run {
            if let onOpenPlant {
                onOpenPlant(plantID)
            } else {
                pendingPlantID = plantID
            }
        }
    }
}
