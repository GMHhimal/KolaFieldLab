//
//  Logging.swift
//  KolaCare
//
//  Unified logging categories (view in Console.app or Xcode's debug console).
//

import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "KolaCare"

    static let diagnosis = Logger(subsystem: subsystem, category: "diagnosis")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}

/// Signposts make the diagnosis pipeline visible in Instruments › Points of Interest.
enum Signposts {
    static let diagnosis = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "KolaCare", category: .pointsOfInterest)
}
