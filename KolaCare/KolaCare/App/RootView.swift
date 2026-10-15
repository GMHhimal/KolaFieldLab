//
//  RootView.swift
//  KolaCare
//
//  Top-level container: onboarding on first launch, then a five-tab interface.
//  Each tab owns a NavigationStack bound to the router's path.
//

import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage(AppSettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            if hasCompletedOnboarding {
                MainTabView()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.5)) { hasCompletedOnboarding = true }
                }
                .transition(.opacity)
            }
        }
        .task {
            // Deep link from a tapped follow-up reminder.
            NotificationService.shared.onOpenPlant = { plantID in openPlant(plantID) }
            if let pending = NotificationService.shared.consumePendingPlantID() { openPlant(pending) }
        }
    }

    private func openPlant(_ id: UUID) {
        guard let plant = GardenRepository(context: modelContext).plant(withID: id) else { return }
        router.openPlant(plant)
    }
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.homePath) {
                DashboardView()
                    .appNavigationDestinations()
            }
            .tabItem { Label { Text(AppTab.home.title) } icon: { Image(systemName: AppTab.home.symbol) } }
            .tag(AppTab.home)

            NavigationStack(path: $router.gardenPath) {
                GardenView()
            }
            .tabItem { Label { Text(AppTab.garden.title) } icon: { Image(systemName: AppTab.garden.symbol) } }
            .tag(AppTab.garden)

            NavigationStack(path: $router.scanPath) {
                ScanView()
                    .appNavigationDestinations()
            }
            .tabItem { Label { Text(AppTab.scan.title) } icon: { Image(systemName: AppTab.scan.symbol) } }
            .tag(AppTab.scan)

            NavigationStack(path: $router.mapPath) {
                FieldMapView()
                    .appNavigationDestinations()
            }
            .tabItem { Label { Text(AppTab.map.title) } icon: { Image(systemName: AppTab.map.symbol) } }
            .tag(AppTab.map)

            NavigationStack(path: $router.libraryPath) {
                DiseaseLibraryView()
                    .appNavigationDestinations()
            }
            .tabItem { Label { Text(AppTab.library.title) } icon: { Image(systemName: AppTab.library.symbol) } }
            .tag(AppTab.library)
        }
        .sensoryFeedback(.selection, trigger: router.selectedTab)
    }
}

// MARK: - Shared navigation destinations

extension View {
    /// Registers the app's typed navigation destinations once per stack.
    /// `zoomNamespace` enables the iOS 18 zoom transition from a plant card.
    func appNavigationDestinations(zoomNamespace: Namespace.ID? = nil) -> some View {
        self
            .navigationDestination(for: Plant.self) { plant in
                PlantDetailView(plant: plant)
                    .zoomDestination(id: plant.id, in: zoomNamespace)
            }
            .navigationDestination(for: ScanRecord.self) { scan in
                ScanDetailView(scan: scan)
            }
            .navigationDestination(for: Disease.self) { disease in
                DiseaseDetailView(disease: disease)
            }
    }
}
