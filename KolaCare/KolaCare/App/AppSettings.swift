//
//  AppSettings.swift
//  KolaCare
//
//  User preferences persisted with @AppStorage (UserDefaults).
//

import SwiftUI

enum AppSettingsKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding"
    static let appearance = "appearance"
    static let palette = "palette"
    static let followUpDays = "followUpDays"
    static let favouriteCrops = "favouriteCrops"
    static let lesionOverlayDefault = "lesionOverlayDefault"
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Crops chosen during onboarding, stored as a comma-separated string so it fits @AppStorage.
struct CropSelection: RawRepresentable, Equatable {
    var crops: Set<Crop>

    init(crops: Set<Crop>) { self.crops = crops }

    init?(rawValue: String) {
        crops = Set(rawValue.split(separator: ",").compactMap { Crop(rawValue: String($0)) })
    }

    var rawValue: String { crops.map(\.rawValue).sorted().joined(separator: ",") }

    static let defaultSelection = CropSelection(crops: [.tomato, .chilli, .rice])
}

/// Launch arguments used by UI tests to start from a known state.
enum LaunchArguments {
    static let uiTesting = "-uiTesting"
    static let resetOnboarding = "-resetOnboarding"
    static let skipOnboarding = "-skipOnboarding"
    static let seedDemoData = "-seedDemoData"

    static var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains(uiTesting) }

    static func contains(_ argument: String) -> Bool { ProcessInfo.processInfo.arguments.contains(argument) }
}
