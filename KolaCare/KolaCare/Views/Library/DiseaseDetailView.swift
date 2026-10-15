//
//  DiseaseDetailView.swift
//  KolaCare
//
//  Field guide for one disease: symptoms, favourable weather, organic vs.
//  chemical treatment (segmented control), prevention and expert help.
//

import SwiftUI

struct DiseaseDetailView: View {
    let disease: Disease

    @Environment(\.kolaTheme) private var theme
    @State private var treatmentMode: TreatmentMode = .organic

    enum TreatmentMode: String, CaseIterable, Identifiable {
        case organic, chemical
        var id: String { rawValue }
        var title: LocalizedStringResource {
            switch self {
            case .organic: "Organic & cultural"
            case .chemical: "Chemical"
            }
        }
    }

    private var shareText: String {
        var lines = ["\(disease.crop.emoji) \(disease.names.en) — \(disease.pathogen)", "", disease.summary, "", "Symptoms:"]
        lines += disease.symptoms.map { "• \($0)" }
        lines += ["", "Treatment:"] + disease.treatmentPlan.map { "• \($0)" }
        lines += ["", "Prevention:"] + disease.prevention.map { "• \($0)" }
        lines += ["", "Shared from KolaCare"]
        return lines.joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KolaTheme.spacing) {
                header

                if disease.isHealthy {
                    InfoSection(title: Text("Keep it healthy"), systemImage: "heart.text.square", items: disease.prevention)
                } else {
                    InfoSection(title: Text("Symptoms"), systemImage: "eye", items: disease.symptoms)
                        .staggeredAppear(index: 0)

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: Text("Favourable conditions"), systemImage: "cloud.sun.rain")
                        Text(disease.favourableConditions).font(.body)
                        if let profile = disease.riskProfile {
                            HStack(spacing: 10) {
                                MetricTile(title: Text("Temperature"),
                                           value: "\(Int(profile.minTemp))–\(Int(profile.maxTemp))°C",
                                           systemImage: "thermometer.medium", tint: .orange)
                                if let humidity = profile.minHumidity {
                                    MetricTile(title: Text("Humidity"), value: "≥ \(Int(humidity))%",
                                               systemImage: "humidity.fill", tint: .blue)
                                } else if let humidity = profile.maxHumidity {
                                    MetricTile(title: Text("Humidity"), value: "≤ \(Int(humidity))%",
                                               systemImage: "sun.max.fill", tint: .orange)
                                }
                            }
                        }
                    }
                    .cardStyle()
                    .staggeredAppear(index: 1)

                    treatment.staggeredAppear(index: 2)

                    InfoSection(title: Text("Prevention"), systemImage: "shield.lefthalf.filled", items: disease.prevention)
                        .staggeredAppear(index: 3)
                }

                helpCard.staggeredAppear(index: 4)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .navigationTitle(Text(disease.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText, subject: Text(disease.names.en)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Text("Share guide"))
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(disease.crop.emoji)
                    .font(.system(size: 44))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(disease.name)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    if disease.pathogen != "—" {
                        Text(disease.pathogen)
                            .font(.subheadline)
                            .italic()
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            HStack {
                TagChip(text: Text(disease.type.title), systemImage: disease.type.symbol, tint: .white)
                if disease.contagiousness > 0 {
                    HStack(spacing: 6) {
                        Text("Spread").font(.caption.weight(.medium)).foregroundStyle(.white)
                        ContagiousnessMeter(level: disease.contagiousness)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.18), in: Capsule())
                }
            }
            Text(disease.summary)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.95))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                theme.heroGradient
                LinearGradient(colors: [disease.type.tint.opacity(0.55), .clear], startPoint: .bottomTrailing, endPoint: .topLeading)
                Color.black.opacity(0.18)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var treatment: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: Text("Treatment"), systemImage: "cross.case")
            Picker(selection: $treatmentMode.animation(.snappy)) {
                ForEach(TreatmentMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Text("Treatment type")
            }
            .pickerStyle(.segmented)

            let items = treatmentMode == .organic ? disease.organicTreatment : disease.chemicalTreatment
            if items.isEmpty {
                Text("No chemical treatment recommended — focus on organic and cultural control.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .frame(width: 24, height: 24)
                            .background((treatmentMode == .organic ? Color.green : Color.orange).opacity(0.18), in: Circle())
                        Text(item).font(.body)
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
                .id(treatmentMode)
            }
            if treatmentMode == .chemical {
                Label("Always read the label, wear protective clothing and respect the pre-harvest interval.",
                      systemImage: "exclamationmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .cardStyle()
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: Text("Need expert help?"), systemImage: "person.fill.questionmark")
            Text("Talk to your area's Agriculture Instructor or call the Department of Agriculture's 1920 call centre for free advice.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let url = URL(string: "tel:1920") {
                Link(destination: url) {
                    Label("Call 1920", systemImage: "phone.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .cardStyle()
    }
}

private struct InfoSection: View {
    let title: Text
    let systemImage: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, systemImage: systemImage)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(item).font(.body)
                }
            }
        }
        .cardStyle()
    }
}
