//
//  SettingsView.swift
//  KolaCare
//
//  Appearance and theme, language, crops, reminders, data management
//  (demo data, CSV export, erase) and the about / attribution screen.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Exportable CSV of the whole garden, shared through the system share sheet.
struct GardenCSVFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName("KolaCare-garden.csv")
    }
}

struct SettingsView: View {
    @AppStorage(AppSettingsKey.appearance) private var appearance: AppearanceMode = .system
    @AppStorage(AppSettingsKey.palette) private var palette: ThemePalette = .paddy
    @AppStorage(AppSettingsKey.followUpDays) private var followUpDays = 5
    @AppStorage(AppSettingsKey.favouriteCrops) private var favouriteCrops = CropSelection.defaultSelection
    @AppStorage(AppSettingsKey.lesionOverlayDefault) private var lesionOverlayDefault = true
    @AppStorage(AppSettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = true

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.diseaseCatalog) private var catalog
    @Environment(\.openURL) private var openURL
    @Query private var plants: [Plant]

    @State private var confirmingErase = false
    private let diagnosisService = LeafDiagnosisService.shared

    var body: some View {
        Form {
            Section {
                Picker(selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Colour theme", systemImage: "paintpalette")
                    HStack(spacing: 14) {
                        ForEach(ThemePalette.allCases) { option in
                            PaletteSwatch(palette: option, isSelected: palette == option) {
                                withAnimation(.snappy) { palette = option }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    LabeledContent {
                        Text(Locale.current.localizedString(forLanguageCode: Bundle.main.preferredLocalizations.first ?? "en") ?? "English")
                    } label: {
                        Label("Language (English, සිංහල, தமிழ்)", systemImage: "globe")
                    }
                }
                .foregroundStyle(.primary)
            } header: {
                Text("Look & feel")
            } footer: {
                Text("Change the app language in iOS Settings › KolaCare › Language.")
            }

            Section {
                ForEach(Crop.allCases.filter { $0 != .other }) { crop in
                    Toggle(isOn: Binding(
                        get: { favouriteCrops.crops.contains(crop) },
                        set: { isOn in
                            var crops = favouriteCrops.crops
                            if isOn { crops.insert(crop) } else { crops.remove(crop) }
                            favouriteCrops = CropSelection(crops: crops)
                        })) {
                        Text("\(crop.emoji) \(Text(crop.displayName))")
                    }
                }
            } header: {
                Text("Weather alerts for")
            }

            Section {
                Stepper(value: $followUpDays, in: 1...30) {
                    Label("Re-scan reminder after \(followUpDays) days", systemImage: "bell")
                }
                Toggle(isOn: $lesionOverlayDefault) {
                    Label("Show lesion map by default", systemImage: "square.3.layers.3d.down.right")
                }
            } header: {
                Text("Diagnosis")
            }

            Section {
                LabeledContent {
                    Text(diagnosisService.activeEngine.title)
                } label: {
                    Label("Engine", systemImage: diagnosisService.activeEngine.symbol)
                }
                LabeledContent {
                    Text(diagnosisService.modelName.map { "\($0).mlmodel" } ?? String(localized: "Not installed"))
                } label: {
                    Label("CoreML model", systemImage: "cpu")
                }
                LabeledContent {
                    Text("\(catalog.libraryEntries.count)")
                } label: {
                    Label("Diseases in library", systemImage: "books.vertical")
                }
            } header: {
                Text("On-device AI")
            } footer: {
                Text("All analysis runs on this device. Photos are never uploaded.")
            }

            Section {
                ShareLink(item: GardenCSVFile(text: GardenCSVExporter.csv(for: plants, catalog: catalog)),
                          preview: SharePreview("KolaCare-garden.csv", image: Image(systemName: "tablecells"))) {
                    Label("Export scans as CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(plants.isEmpty)

                Button {
                    withAnimation { DemoDataSeeder.seed(into: modelContext) }
                } label: {
                    Label("Load demo garden", systemImage: "wand.and.stars")
                }
                .accessibilityIdentifier("settings.demo")

                Button {
                    hasCompletedOnboarding = false
                    dismiss()
                } label: {
                    Label("Show onboarding again", systemImage: "sparkles")
                }

                Button(role: .destructive) {
                    confirmingErase = true
                } label: {
                    Label("Erase all data", systemImage: "trash")
                }
                .disabled(plants.isEmpty)
            } header: {
                Text("Data")
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About KolaCare", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle(Text("Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .confirmationDialog(Text("Erase all plants and scans?"), isPresented: $confirmingErase, titleVisibility: .visible) {
            Button("Erase everything", role: .destructive) {
                withAnimation { GardenRepository(context: modelContext).eraseAll() }
                WeatherCache().clear()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
}

private struct PaletteSwatch: View {
    let palette: ThemePalette
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(palette.heroGradient)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Circle().strokeBorder(Color.primary, lineWidth: isSelected ? 3 : 0).padding(-4)
                    }
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                        }
                    }
                Text(palette.title).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(palette.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AboutView: View {
    @Environment(\.kolaTheme) private var theme

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("BrandMark")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(radius: 8, y: 4)
                    Text("KolaCare").font(.title.bold())
                    Text("Your AI leaf doctor").foregroundStyle(.secondary)
                    Text("Version \(version)").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical)
            }
            Section {
                Text("KolaCare (කොළ — “leaf” in Sinhala) helps Sri Lankan farmers and home gardeners spot crop diseases early, act on clear treatment plans and track recovery — all on-device and offline-first.")
            } header: {
                Text("Mission")
            }
            Section {
                LabeledContent("Developer", value: "G M H Himal")
                LabeledContent("Student ID", value: "IT23152632")
                LabeledContent("Module", value: "SE4041 — MADD, SLIIT")
            } header: {
                Text("Credits")
            }
            Section {
                Link(destination: URL(string: "https://open-meteo.com/")!) {
                    Label("Weather data by Open-Meteo.com (CC BY 4.0)", systemImage: "cloud.sun")
                }
                Link(destination: URL(string: "https://github.com/spMohanty/PlantVillage-Dataset")!) {
                    Label("Model training images: PlantVillage dataset", systemImage: "photo.stack")
                }
                Link(destination: URL(string: "https://doa.gov.lk/")!) {
                    Label("Department of Agriculture, Sri Lanka", systemImage: "building.columns")
                }
            } header: {
                Text("Data sources")
            } footer: {
                Text("Treatment information is general guidance. Always follow product labels and local DOA recommendations.")
            }
        }
        .navigationTitle(Text("About"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
