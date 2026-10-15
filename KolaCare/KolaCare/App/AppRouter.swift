//
//  AppRouter.swift
//  KolaCare
//
//  Central navigation state: the selected tab plus one NavigationPath per tab.
//  Owning the paths here enables programmatic navigation (deep links from
//  notifications, "Scan this plant", pop-to-root after saving a diagnosis).
//

import SwiftUI
import Observation

enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, garden, scan, map, library

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .garden: "Garden"
        case .scan: "Scan"
        case .map: "Map"
        case .library: "Library"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .garden: "leaf.fill"
        case .scan: "viewfinder"
        case .map: "map.fill"
        case .library: "books.vertical.fill"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var homePath = NavigationPath()
    var gardenPath = NavigationPath()
    var scanPath = NavigationPath()
    var mapPath = NavigationPath()
    var libraryPath = NavigationPath()

    /// Plant pre-selected when the user taps "Scan this plant".
    var scanTargetPlantID: UUID?

    func openPlant(_ plant: Plant) {
        gardenPath = NavigationPath()
        gardenPath.append(plant)
        selectedTab = .garden
    }

    func startScan(for plantID: UUID?) {
        scanTargetPlantID = plantID
        scanPath = NavigationPath()
        selectedTab = .scan
    }

    func popToRoot(_ tab: AppTab) {
        switch tab {
        case .home: homePath = NavigationPath()
        case .garden: gardenPath = NavigationPath()
        case .scan: scanPath = NavigationPath()
        case .map: mapPath = NavigationPath()
        case .library: libraryPath = NavigationPath()
        }
    }
}
