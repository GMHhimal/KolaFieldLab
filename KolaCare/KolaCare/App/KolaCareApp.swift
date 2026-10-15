//
//  KolaCareApp.swift
//  KolaCare — AI leaf doctor for Sri Lankan farmers and home gardeners
//
//  Author: G M H Himal (IT23152632)
//  SE4041 Mobile Application Design and Development — Assignment 2, Part A
//

import SwiftUI
import SwiftData
import TipKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationService.shared.configure()
        return true
    }
}

@main
struct KolaCareApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @AppStorage(AppSettingsKey.appearance) private var appearance: AppearanceMode = .system
    @AppStorage(AppSettingsKey.palette) private var palette: ThemePalette = .paddy

    @State private var router = AppRouter()
    @State private var locationProvider = LocationProvider()

    private let container: ModelContainer

    init() {
        let uiTesting = LaunchArguments.isUITesting
        let container = PersistenceController.makeContainer(inMemory: uiTesting)
        self.container = container

        // Deterministic starting state for UI tests.
        if LaunchArguments.contains(LaunchArguments.resetOnboarding) {
            UserDefaults.standard.set(false, forKey: AppSettingsKey.hasCompletedOnboarding)
        }
        if LaunchArguments.contains(LaunchArguments.skipOnboarding) {
            UserDefaults.standard.set(true, forKey: AppSettingsKey.hasCompletedOnboarding)
        }
        if LaunchArguments.contains(LaunchArguments.seedDemoData) {
            MainActor.assumeIsolated { DemoDataSeeder.seed(into: container.mainContext) }
        }

        if uiTesting {
            Tips.hideAllTipsForTesting()
        }
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(locationProvider)
                .environment(\.kolaTheme, KolaTheme(palette: palette))
                .environment(\.diseaseCatalog, .shared)
                .tint(palette.accent)
                .fontDesign(.rounded)
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container)
    }
}
