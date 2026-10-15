//
//  OnboardingView.swift
//  KolaCare
//
//  First-launch introduction: three animated feature pages and a crop picker
//  that personalises the weather-based disease alerts.
//

import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @AppStorage(AppSettingsKey.favouriteCrops) private var favouriteCrops = CropSelection.defaultSelection
    @Environment(\.kolaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LocationProvider.self) private var locationProvider
    @State private var page = 0
    @State private var selectedCrops: Set<Crop> = CropSelection.defaultSelection.crops

    private struct Feature: Identifiable {
        let id: Int
        let symbol: String
        let title: LocalizedStringResource
        let message: LocalizedStringResource
    }

    private let features: [Feature] = [
        Feature(id: 0, symbol: "camera.viewfinder", title: "Diagnose in seconds",
                message: "Photograph a leaf and KolaCare's on-device AI names the disease and measures how much of the leaf is affected."),
        Feature(id: 1, symbol: "cloud.sun.rain.fill", title: "Stay ahead of the weather",
                message: "Hourly forecasts are turned into early warnings for blight, blast and other diseases before they spread."),
        Feature(id: 2, symbol: "checklist", title: "Treat and track",
                message: "Follow step-by-step organic and chemical treatment plans, map your plots and watch recovery over time.")
    ]

    private var lastPage: Int { features.count }

    var body: some View {
        ZStack {
            theme.heroGradient.opacity(0.22).ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Image("BrandMark")
                        .resizable()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                    Text("KolaCare").font(.title3.bold())
                    Spacer()
                    if page < lastPage {
                        Button("Skip") { withAnimation { page = lastPage } }
                            .accessibilityIdentifier("onboarding.skip")
                    }
                }
                .padding(.horizontal)

                TabView(selection: $page) {
                    ForEach(features) { feature in
                        FeaturePage(symbol: feature.symbol, title: feature.title, message: feature.message,
                                    isActive: page == feature.id)
                            .tag(feature.id)
                    }
                    cropPicker.tag(lastPage)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: page)

                PageIndicator(count: features.count + 1, current: page)

                Button {
                    if page < lastPage {
                        withAnimation { page += 1 }
                    } else {
                        favouriteCrops = CropSelection(crops: selectedCrops.isEmpty ? CropSelection.defaultSelection.crops : selectedCrops)
                        locationProvider.requestPermission()
                        onFinish()
                    }
                } label: {
                    Text(page < lastPage ? LocalizedStringKey("Next") : LocalizedStringKey("Get started"))
                        .contentTransition(.interpolate)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal)
                .accessibilityIdentifier("onboarding.next")
            }
            .padding(.vertical)
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    private var cropPicker: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(theme.accent)
                    .symbolEffect(.bounce, value: page == lastPage)
                    .accessibilityHidden(true)
                Text("What do you grow?")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("We'll watch the weather for diseases that affect these crops. You can change this later.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(Crop.allCases.filter { $0 != .other }) { crop in
                        let selected = selectedCrops.contains(crop)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if selected { selectedCrops.remove(crop) } else { selectedCrops.insert(crop) }
                            }
                        } label: {
                            HStack {
                                Text(crop.emoji).font(.title2)
                                Text(crop.displayName).font(.headline)
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? theme.accent : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding()
                            .frame(minHeight: 56)
                            .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(selected ? theme.accent : .clear, lineWidth: 2)
                            }
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("onboarding.crop.\(crop.rawValue)")
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct FeaturePage: View {
    let symbol: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let isActive: Bool

    @Environment(\.kolaTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 96
    @State private var pulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(theme.accent.opacity(0.12))
                        .frame(width: iconSize * 2.1, height: iconSize * 2.1)
                        .scaleEffect(pulse ? 1.08 : 0.94)
                    Circle()
                        .fill(theme.accent.opacity(0.18))
                        .frame(width: iconSize * 1.5, height: iconSize * 1.5)
                    Image(systemName: symbol)
                        .font(.system(size: iconSize * 0.62, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .symbolRenderingMode(.hierarchical)
                        .symbolEffect(.bounce, value: isActive)
                }
                .padding(.top, 24)
                .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text(message)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                .opacity(isActive ? 1 : 0.3)
                .offset(y: isActive ? 0 : 20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isActive)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// Capsule page indicator whose active dot stretches with a spring.
private struct PageIndicator: View {
    let count: Int
    let current: Int
    @Environment(\.kolaTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? theme.accent : Color.secondary.opacity(0.3))
                    .frame(width: index == current ? 26 : 8, height: 8)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(current + 1) of \(count)"))
    }
}
