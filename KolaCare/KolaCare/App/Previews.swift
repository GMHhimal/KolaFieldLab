//
//  Previews.swift
//  KolaCare
//
//  Xcode canvas previews backed by the in-memory demo garden.
//

#if DEBUG
import SwiftData
import SwiftUI

private struct PreviewEnvironment: ViewModifier {
    @State private var router = AppRouter()
    @State private var location = LocationProvider()

    func body(content: Content) -> some View {
        content
            .environment(router)
            .environment(location)
            .modelContainer(PersistenceController.preview)
    }
}

extension View {
    func previewEnvironment() -> some View { modifier(PreviewEnvironment()) }
}

#Preview("App") {
    MainTabView().previewEnvironment()
}

#Preview("Dashboard – dark") {
    NavigationStack { DashboardView() }
        .previewEnvironment()
        .preferredColorScheme(.dark)
}

#Preview("Garden – large text") {
    NavigationStack { GardenView() }
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("Library – Sinhala") {
    NavigationStack { DiseaseLibraryView() }
        .previewEnvironment()
        .environment(\.locale, Locale(identifier: "si"))
}

#Preview("Onboarding") {
    OnboardingView(onFinish: {}).previewEnvironment()
}
#endif
