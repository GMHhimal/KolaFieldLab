//
//  DiagnosisResultView.swift
//  KolaCare
//
//  Shows the diagnosis with an animated, staggered reveal: zoomable photo with
//  lesion map, health / confidence / severity, quality warnings, alternative
//  predictions, first treatment steps, and saving to a plant in the garden.
//

import SwiftData
import SwiftUI

struct DiagnosisResultView: View {
    let viewModel: ScanViewModel
    var preselectedPlantID: UUID?
    var onDone: () -> Void

    @Environment(\.diseaseCatalog) private var catalog
    @Environment(\.kolaTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @AppStorage(AppSettingsKey.followUpDays) private var followUpDays = 5
    @AppStorage(AppSettingsKey.lesionOverlayDefault) private var lesionOverlayDefault = true
    @Query(sort: \Plant.name) private var plants: [Plant]

    @State private var showsLesionMap = true
    @State private var selectedPlantID: UUID?
    @State private var notes = ""
    @State private var remind = true
    @State private var showingNewPlant = false
    @State private var saved = false

    var body: some View {
        if let result = viewModel.result, let image = viewModel.image {
            content(result: result, image: image)
        } else {
            ContentUnavailableView("No result", systemImage: "leaf")
        }
    }

    private func content(result: DiagnosisResult, image: UIImage) -> some View {
        let disease = catalog.disease(id: result.diseaseID)
        return ScrollView {
            VStack(spacing: KolaTheme.spacing) {
                photoCard(result: result, image: image)
                    .staggeredAppear(index: 0)
                headerCard(result: result, disease: disease)
                    .staggeredAppear(index: 1)
                if !result.warnings.isEmpty {
                    warningsCard(result.warnings).staggeredAppear(index: 2)
                }
                if result.predictions.count > 1 {
                    alternativesCard(result).staggeredAppear(index: 3)
                }
                if let disease {
                    treatmentPreview(disease).staggeredAppear(index: 4)
                }
                saveCard(result: result, disease: disease)
                    .staggeredAppear(index: 5)
                Text("KolaCare gives guidance, not a guaranteed diagnosis. For serious outbreaks contact your Agriculture Instructor or the DOA 1920 call centre.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle(Text("Diagnosis"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onDone)
            }
        }
        .onAppear {
            showsLesionMap = lesionOverlayDefault
            if selectedPlantID == nil {
                selectedPlantID = preselectedPlantID ?? suggestedPlant(for: disease)?.id
            }
        }
        .sheet(isPresented: $showingNewPlant) {
            NavigationStack {
                AddPlantView(initialCrop: disease?.crop) { plant in
                    selectedPlantID = plant.id
                }
            }
        }
    }

    /// Picks the first plant of the diagnosed crop, if any.
    private func suggestedPlant(for disease: Disease?) -> Plant? {
        guard let crop = disease?.crop, crop != .other else { return plants.first }
        return plants.first { $0.crop == crop } ?? plants.first
    }

    // MARK: Cards

    private func photoCard(result: DiagnosisResult, image: UIImage) -> some View {
        VStack(spacing: 10) {
            ZoomableImageView(image: image, overlay: result.lesionMap, showsOverlay: showsLesionMap)
                .frame(height: 300)
                .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if result.lesionMap != nil {
                Toggle(isOn: $showsLesionMap.animation()) {
                    Label("Show lesion map", systemImage: "square.3.layers.3d.down.right")
                }
                .accessibilityIdentifier("result.lesionToggle")
                HStack(spacing: 16) {
                    LegendDot(color: Color(red: 1, green: 0.69, blue: 0), title: Text("Yellowing"))
                    LegendDot(color: Color(red: 0.9, green: 0.08, blue: 0.24), title: Text("Dead tissue"))
                    Spacer()
                }
                .font(.caption)
            }
        }
        .cardStyle(padding: 12)
    }

    private func headerCard(result: DiagnosisResult, disease: Disease?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(disease.map { "\($0.crop.emoji) \($0.name)" } ?? result.diseaseID)
                        .font(.title2.bold())
                        .accessibilityIdentifier("result.diseaseName")
                    if let disease, disease.pathogen != "—" {
                        Text(disease.pathogen).font(.subheadline).italic().foregroundStyle(.secondary)
                    }
                    HStack {
                        if let disease {
                            TagChip(text: Text(disease.type.title), systemImage: disease.type.symbol, tint: disease.type.tint)
                        }
                        TagChip(text: Text(result.engine.title), systemImage: result.engine.symbol, tint: .secondary)
                    }
                }
                Spacer()
                SeverityBadge(severity: result.severity)
            }

            HStack(spacing: 16) {
                HealthRing(score: result.healthScore)
                    .frame(width: 92, height: 92)
                VStack(spacing: 10) {
                    ConfidenceBar(label: String(localized: "Confidence"), confidence: result.confidence, tint: theme.accent)
                    ConfidenceBar(label: String(localized: "Leaf area affected"), confidence: result.metrics.affectedArea,
                                  tint: result.severity.color)
                }
            }

            HStack(spacing: 10) {
                MetricTile(title: Text("Yellowing"),
                           value: result.metrics.chlorosisFraction.formatted(.percent.precision(.fractionLength(0))),
                           systemImage: "circle.lefthalf.filled", tint: .yellow)
                MetricTile(title: Text("Dead tissue"),
                           value: result.metrics.necrosisFraction.formatted(.percent.precision(.fractionLength(0))),
                           systemImage: "circle.fill", tint: .brown)
                MetricTile(title: Text("Leaf in frame"),
                           value: result.metrics.leafCoverage.formatted(.percent.precision(.fractionLength(0))),
                           systemImage: "viewfinder", tint: .teal)
            }

            if let disease {
                Text(disease.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func warningsCard(_ warnings: [QualityWarning]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(warnings, id: \.self) { warning in
                Label { Text(warning.message) } icon: {
                    Image(systemName: warning.symbol).foregroundStyle(.orange)
                }
                .font(.subheadline)
            }
        }
        .cardStyle()
        .overlay {
            RoundedRectangle(cornerRadius: KolaTheme.cornerRadius, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1)
        }
        .accessibilityIdentifier("result.warnings")
    }

    private func alternativesCard(_ result: DiagnosisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: Text("Other possibilities"), systemImage: "list.number")
            ForEach(result.predictions.dropFirst()) { prediction in
                if let disease = catalog.disease(id: prediction.diseaseID) {
                    NavigationLink(value: disease) {
                        ConfidenceBar(label: "\(disease.crop.emoji) \(disease.name)", confidence: prediction.confidence, tint: .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .cardStyle()
    }

    private func treatmentPreview(_ disease: Disease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: Text("What to do now"), systemImage: "cross.case.fill")
            ForEach(Array(disease.organicTreatment.prefix(3).enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .frame(width: 22, height: 22)
                        .background(theme.accent.opacity(0.18), in: Circle())
                    Text(step).font(.subheadline)
                }
            }
            NavigationLink(value: disease) {
                Label("Full treatment guide", systemImage: "book.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .cardStyle()
    }

    @ViewBuilder
    private func saveCard(result: DiagnosisResult, disease: Disease?) -> some View {
        if saved {
            SavedConfirmation(
                onViewPlant: {
                    if let plant = viewModel.savedRecord?.plant {
                        onDone()
                        router.openPlant(plant)
                    }
                },
                onScanAnother: onDone)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: Text("Save to garden"), systemImage: "tray.and.arrow.down.fill")

                if plants.isEmpty {
                    Text("Create a plant to keep a history of its scans.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(selection: $selectedPlantID) {
                        Text("Choose a plant").tag(UUID?.none)
                        ForEach(plants) { plant in
                            Text("\(plant.crop.emoji) \(plant.name)").tag(Optional(plant.id))
                        }
                    } label: {
                        Text("Plant")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("result.plantPicker")
                }

                Button {
                    showingNewPlant = true
                } label: {
                    Label("New plant", systemImage: "plus")
                }
                .accessibilityIdentifier("result.newPlant")

                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)

                Toggle(isOn: $remind) {
                    Text("Remind me to re-scan in \(followUpDays) days")
                }
                if remind {
                    Stepper(value: $followUpDays, in: 1...30) {
                        Text("\(followUpDays) days").foregroundStyle(.secondary)
                    }
                }

                Button {
                    save()
                } label: {
                    Label("Save diagnosis", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedPlant == nil)
                .accessibilityIdentifier("result.save")
            }
            .cardStyle()
        }
    }

    private var selectedPlant: Plant? {
        guard let selectedPlantID else { return nil }
        return plants.first { $0.id == selectedPlantID }
    }

    private func save() {
        guard let plant = selectedPlant else { return }
        viewModel.save(to: plant, notes: notes, followUpInDays: remind ? followUpDays : nil, context: modelContext)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { saved = true }
    }
}

private struct LegendDot: View {
    let color: Color
    let title: Text

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 10, height: 10)
            title.foregroundStyle(.secondary)
        }
    }
}

/// Animated checkmark shown after saving.
private struct SavedConfirmation: View {
    var onViewPlant: () -> Void
    var onScanAnother: () -> Void

    @State private var drawn = false
    @Environment(\.kolaTheme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.15)).frame(width: 84, height: 84)
                Image(systemName: "checkmark")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .scaleEffect(drawn ? 1 : 0.2)
                    .opacity(drawn ? 1 : 0)
            }
            Text("Saved to your garden").font(.headline)
            HStack(spacing: 12) {
                Button("View plant", action: onViewPlant).buttonStyle(SecondaryButtonStyle())
                Button("Scan another", action: onScanAnother).buttonStyle(PrimaryButtonStyle())
            }
        }
        .cardStyle()
        .sensoryFeedback(.success, trigger: drawn)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.1)) { drawn = true }
        }
        .accessibilityIdentifier("result.saved")
    }
}
