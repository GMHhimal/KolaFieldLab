//
//  DashboardView.swift
//  KolaCare
//
//  Home screen: garden health at a glance, weather-driven disease alerts,
//  plants needing attention and scan activity. Adapts to a two-column layout
//  on iPad and in landscape.
//

import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Plant.createdAt, order: .reverse) private var plants: [Plant]
    @Query(sort: \ScanRecord.date, order: .reverse) private var scans: [ScanRecord]

    @AppStorage(AppSettingsKey.favouriteCrops) private var favouriteCrops = CropSelection.defaultSelection
    @Environment(AppRouter.self) private var router
    @Environment(LocationProvider.self) private var locationProvider
    @Environment(\.kolaTheme) private var theme
    @Environment(\.diseaseCatalog) private var catalog
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel = DashboardViewModel()
    @State private var showingSettings = false

    private var monitoredCrops: Set<Crop> {
        favouriteCrops.crops.union(plants.map(\.crop)).subtracting([.other])
    }

    private var plantsNeedingAttention: [Plant] {
        plants.filter { ($0.healthScore ?? 100) < 76 }
            .sorted { ($0.healthScore ?? 100) < ($1.healthScore ?? 100) }
    }

    private var averageHealth: Int? {
        let scores = plants.compactMap(\.healthScore)
        guard !scores.isEmpty else { return nil }
        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }

    var body: some View {
        ScrollView {
            if sizeClass == .regular {
                HStack(alignment: .top, spacing: KolaTheme.spacing) {
                    VStack(spacing: KolaTheme.spacing) {
                        summaryCard.staggeredAppear(index: 0)
                        attentionSection.staggeredAppear(index: 2)
                        recentScansSection.staggeredAppear(index: 4)
                    }
                    VStack(spacing: KolaTheme.spacing) {
                        WeatherRiskCard(viewModel: viewModel, onRetry: { Task { await refresh(force: true) } })
                            .staggeredAppear(index: 1)
                        activityChart.staggeredAppear(index: 3)
                    }
                }
                .padding()
            } else {
                VStack(spacing: KolaTheme.spacing) {
                    summaryCard.staggeredAppear(index: 0)
                    WeatherRiskCard(viewModel: viewModel, onRetry: { Task { await refresh(force: true) } })
                        .staggeredAppear(index: 1)
                    attentionSection.staggeredAppear(index: 2)
                    activityChart.staggeredAppear(index: 3)
                    recentScansSection.staggeredAppear(index: 4)
                }
                .padding()
            }
        }
        .background(theme.background)
        .navigationTitle(Text(greeting))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(Text("Settings"))
                .accessibilityIdentifier("dashboard.settings")
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack { SettingsView() }
        }
        .refreshable { await refresh(force: true) }
        .task { await refresh(force: false) }
        .onChange(of: monitoredCrops) { _, crops in viewModel.updateCrops(crops) }
    }

    private func refresh(force: Bool) async {
        await viewModel.load(crops: monitoredCrops,
                             coordinate: { await locationProvider.coordinateForWeather() },
                             force: force)
    }

    private var greeting: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    // MARK: Sections

    private var summaryCard: some View {
        HStack(spacing: 20) {
            HealthRing(score: averageHealth, lineWidth: 12)
                .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 8) {
                Text("Garden health")
                    .font(.headline)
                if plants.isEmpty {
                    Text("Add your first plant or load the demo garden to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Add plant") { router.selectedTab = .garden }
                        Button("Demo garden") { DemoDataSeeder.seed(into: modelContext) }
                            .accessibilityIdentifier("dashboard.demo")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text("\(plants.count) plants · \(scans.count) scans")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(Severity.allCases, id: \.self) { severity in
                            let count = plants.filter { $0.severity == severity }.count
                            if count > 0 {
                                HStack(spacing: 3) {
                                    Circle().fill(severity.color).frame(width: 8, height: 8)
                                    Text("\(count)").font(.caption.monospacedDigit())
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("\(count) \(Text(severity.title))"))
                            }
                        }
                    }
                    Button {
                        router.startScan(for: nil)
                    } label: {
                        Label("Scan a leaf", systemImage: "viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
        .overlay(alignment: .topTrailing) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 64))
                .foregroundStyle(theme.accent.opacity(0.08))
                .rotationEffect(.degrees(-25))
                .padding(8)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var attentionSection: some View {
        if !plantsNeedingAttention.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: Text("Needs attention"), systemImage: "exclamationmark.triangle.fill")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(plantsNeedingAttention) { plant in
                            NavigationLink(value: plant) {
                                AttentionCard(plant: plant, diseaseName: plant.latestScan.flatMap { catalog.disease(id: $0.diseaseID)?.name })
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
            .cardStyle()
        }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: Text("Scan activity"), systemImage: "chart.bar.fill")
            let weekly = ScanActivity.weekly(scans: scans, weeks: 6)
            if weekly.isEmpty {
                Text("Your scans from the last six weeks will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(weekly) { item in
                    BarMark(x: .value("Week", item.weekStart, unit: .weekOfYear),
                            y: .value("Scans", item.count))
                        .foregroundStyle(by: .value("Result", item.severityTitle))
                        .cornerRadius(4)
                }
                .chartForegroundStyleScale(domain: Severity.allCases.map { String(localized: $0.title) },
                                           range: Severity.allCases.map(\.color))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    }
                }
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 190)
                .accessibilityLabel(Text("Scans per week by severity"))
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var recentScansSection: some View {
        if !scans.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: Text("Recent scans"), systemImage: "clock.arrow.circlepath")
                    .padding(.bottom, 8)
                ForEach(scans.prefix(4)) { scan in
                    NavigationLink(value: scan) {
                        ScanRow(scan: scan, showsPlantName: true)
                    }
                    .buttonStyle(.plain)
                    if scan.id != scans.prefix(4).last?.id { Divider() }
                }
            }
            .cardStyle()
        }
    }
}

// MARK: - Supporting views

private struct AttentionCard: View {
    let plant: Plant
    let diseaseName: String?
    @Environment(\.kolaTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                PlantThumbnail(data: plant.displayImageData, crop: plant.crop, cornerRadius: 14)
                    .frame(width: 150, height: 96)
                if let severity = plant.severity {
                    SeverityBadge(severity: severity, compact: true).padding(6)
                }
            }
            Text(plant.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(diseaseName ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 150)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}

/// Weekly scan counts grouped by severity, for the activity chart.
struct ScanActivity: Identifiable, Equatable {
    let weekStart: Date
    let severityTitle: String
    let count: Int
    var id: String { "\(weekStart.timeIntervalSince1970)-\(severityTitle)" }

    static func weekly(scans: [ScanRecord], weeks: Int, now: Date = .now, calendar: Calendar = .current) -> [ScanActivity] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let earliest = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: currentWeek) else { return [] }
        var buckets: [Date: [Severity: Int]] = [:]
        for scan in scans where scan.date >= earliest {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: scan.date)?.start else { continue }
            buckets[week, default: [:]][scan.severity, default: 0] += 1
        }
        return buckets.keys.sorted().flatMap { week in
            Severity.allCases.compactMap { severity in
                guard let count = buckets[week]?[severity], count > 0 else { return nil }
                return ScanActivity(weekStart: week, severityTitle: String(localized: severity.title), count: count)
            }
        }
    }
}
