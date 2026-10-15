//
//  ScanDetailView.swift
//  KolaCare
//
//  A saved diagnosis with its interactive treatment checklist. Ticking steps is
//  persisted immediately through SwiftData's observation of the model.
//

import SwiftData
import SwiftUI

struct ScanDetailView: View {
    @Bindable var scan: ScanRecord

    @Environment(\.diseaseCatalog) private var catalog
    @Environment(\.kolaTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var confirmingDelete = false

    private var disease: Disease? { catalog.disease(id: scan.diseaseID) }

    var body: some View {
        List {
            Section {
                ZStack {
                    if let image {
                        ZoomableImageView(image: image, overlay: nil, showsOverlay: false)
                    } else {
                        ProgressView()
                    }
                }
                .frame(height: 260)
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .background(Color.black.opacity(0.85))
            }

            Section {
                HStack(spacing: 16) {
                    HealthRing(score: scan.healthScore, lineWidth: 8)
                        .frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(disease.map { "\($0.crop.emoji) \($0.name)" } ?? scan.diseaseID)
                            .font(.headline)
                        Text(scan.date, format: .dateTime.weekday(.wide).day().month().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            SeverityBadge(severity: scan.severity)
                            if let plant = scan.plant {
                                Text(plant.name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                LabeledContent {
                    Text(scan.affectedArea, format: .percent.precision(.fractionLength(0)))
                } label: {
                    Label("Leaf area affected", systemImage: "square.dashed.inset.filled")
                }
                LabeledContent {
                    Text(scan.confidence, format: .percent.precision(.fractionLength(0)))
                } label: {
                    Label("Confidence", systemImage: "gauge.with.dots.needle.67percent")
                }
                LabeledContent {
                    Text(scan.engine.title)
                } label: {
                    Label("Analysed with", systemImage: scan.engine.symbol)
                }
            }

            if let disease, !disease.treatmentPlan.isEmpty {
                Section {
                    ProgressView(value: scan.treatmentProgress(totalSteps: disease.treatmentPlan.count)) {
                        Text("Treatment progress")
                    }
                    .tint(theme.accent)
                    .animation(.spring, value: scan.completedSteps)

                    ForEach(Array(disease.treatmentPlan.enumerated()), id: \.offset) { index, step in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { scan.toggleStep(index) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: scan.isStepDone(index) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(scan.isStepDone(index) ? theme.accent : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step)
                                        .strikethrough(scan.isStepDone(index))
                                        .foregroundStyle(scan.isStepDone(index) ? Color.secondary : Color.primary)
                                    if index >= disease.organicTreatment.count {
                                        Text("Chemical option — follow the label").font(.caption).foregroundStyle(.orange)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.impact(weight: .light), trigger: scan.isStepDone(index))
                        .accessibilityAddTraits(scan.isStepDone(index) ? .isSelected : [])
                    }
                } header: {
                    Text("Treatment plan")
                } footer: {
                    NavigationLink(value: disease) {
                        Text("Open the full \(disease.name) guide")
                    }
                    .font(.footnote)
                }
            }

            Section {
                if let followUp = scan.followUpDate {
                    LabeledContent {
                        Text(followUp, format: .dateTime.day().month().hour().minute())
                    } label: {
                        Label("Re-scan reminder", systemImage: "bell.badge")
                    }
                }
                TextField("Notes", text: $scan.notes, axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("Follow-up")
            }

            Section {
                Button("Delete scan", role: .destructive) { confirmingDelete = true }
            }
        }
        .navigationTitle(Text("Scan"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scan.id) {
            guard let data = scan.imageData ?? scan.thumbnailData else { return }
            image = await Task.detached(priority: .userInitiated) {
                ImageProcessing.downsample(data, maxPixelSize: 1024).map { UIImage(cgImage: $0) }
            }.value
        }
        .confirmationDialog(Text("Delete this scan?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let repository = GardenRepository(context: modelContext)
                dismiss()
                repository.delete(scan)
            }
        }
    }
}
