//
//  PlantDetailView.swift
//  KolaCare
//
//  One plant: parallax hero header, health trend chart, scan timeline and
//  location. Toolbar actions jump straight to scanning this plant.
//

import Charts
import MapKit
import SwiftData
import SwiftUI

struct PlantDetailView: View {
    @Bindable var plant: Plant

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.kolaTheme) private var theme
    @Environment(\.diseaseCatalog) private var catalog

    @State private var showingEdit = false
    @State private var confirmingDelete = false

    private var scans: [ScanRecord] { plant.sortedScans }

    var body: some View {
        ScrollView {
            VStack(spacing: KolaTheme.spacing) {
                hero
                VStack(spacing: KolaTheme.spacing) {
                    statsRow.staggeredAppear(index: 0)
                    HealthTrendChart(scans: scans).staggeredAppear(index: 1)
                    timeline.staggeredAppear(index: 2)
                    if let coordinate = plant.coordinate {
                        locationCard(coordinate).staggeredAppear(index: 3)
                    }
                    if !plant.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: Text("Notes"), systemImage: "note.text")
                            Text(plant.notes).font(.body)
                        }
                        .cardStyle()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .frame(maxWidth: 760)
            }
            .frame(maxWidth: .infinity)
        }
        .background(theme.background)
        .ignoresSafeArea(edges: .top)
        .navigationTitle(Text(plant.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    router.startScan(for: plant.id)
                } label: {
                    Image(systemName: "viewfinder")
                }
                .accessibilityLabel(Text("Scan this plant"))
                Menu {
                    Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("More"))
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack { AddPlantView(editing: plant) }
        }
        .confirmationDialog(Text("Delete \(plant.name)?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete plant and its scans", role: .destructive) {
                let repository = GardenRepository(context: modelContext)
                dismiss()
                repository.delete(plant)
            }
        }
    }

    // MARK: Hero with parallax

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            PlantThumbnail(data: plant.displayImageData, crop: plant.crop, cornerRadius: 0)
                .frame(height: 300)
                .frame(maxWidth: .infinity)
                .clipped()
                .visualEffect { content, proxy in
                    // Stretch when pulled down, drift slower than the scroll when pushed up.
                    let minY = proxy.frame(in: .scrollView).minY
                    return content
                        .scaleEffect(minY > 0 ? 1 + minY / 300 : 1, anchor: .bottom)
                        .offset(y: minY > 0 ? -minY / 2 : -minY * 0.35)
                }

            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(plant.crop.emoji) \(Text(plant.crop.displayName))")
                        .font(.subheadline.weight(.semibold))
                    Text(plant.name)
                        .font(.largeTitle.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if !plant.plotName.isEmpty {
                        Label(plant.plotName, systemImage: "mappin.and.ellipse").font(.subheadline)
                    }
                }
                .foregroundStyle(.white)
                Spacer()
                HealthRing(score: plant.healthScore, lineWidth: 8)
                    .frame(width: 84, height: 84)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
        }
        .frame(height: 300)
        .clipped()
        .accessibilityElement(children: .combine)
    }

    // MARK: Stats

    private var statsRow: some View {
        let latest = plant.latestScan
        return HStack(spacing: 10) {
            MetricTile(title: Text("Scans"), value: "\(scans.count)", systemImage: "camera.viewfinder")
            MetricTile(title: Text("Last scan"),
                       value: latest.map { $0.date.formatted(.relative(presentation: .named)) } ?? "–",
                       systemImage: "clock", tint: .blue)
            MetricTile(title: Text("Treatment done"),
                       value: latest.flatMap { scan in
                           catalog.disease(id: scan.diseaseID).map { disease in
                               scan.treatmentProgress(totalSteps: disease.treatmentPlan.count)
                                   .formatted(.percent.precision(.fractionLength(0)))
                           }
                       } ?? "–",
                       systemImage: "checklist", tint: .purple)
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: Text("Scan history"), systemImage: "clock.arrow.circlepath",
                          trailing: AnyView(
                            Button {
                                router.startScan(for: plant.id)
                            } label: {
                                Label("Scan", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                            }))
                .padding(.bottom, 8)

            if scans.isEmpty {
                Text("No scans yet. Scan a leaf to start tracking this plant's health.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(scans.enumerated()), id: \.element.id) { index, scan in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(scan.severity.color)
                                .frame(width: 12, height: 12)
                                .padding(.top, 26)
                            if index < scans.count - 1 {
                                Rectangle().fill(Color.secondary.opacity(0.25)).frame(width: 2)
                            }
                        }
                        .frame(width: 12)
                        .accessibilityHidden(true)
                        NavigationLink(value: scan) {
                            ScanRow(scan: scan)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardStyle()
    }

    private func locationCard(_ coordinate: CLLocationCoordinate2D) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: Text("Location"), systemImage: "map")
            Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 500, longitudinalMeters: 500)),
                interactionModes: []) {
                Marker(plant.name, systemImage: "leaf.fill", coordinate: coordinate)
                    .tint(plant.severity?.color ?? .green)
            }
            .mapStyle(.hybrid(elevation: .flat))
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture { router.mapPath = NavigationPath(); router.selectedTab = .map }
            .accessibilityLabel(Text("Plot location map. Opens the field map."))
            .accessibilityAddTraits(.isButton)
        }
        .cardStyle()
    }
}

// MARK: - Health trend chart

struct HealthTrendChart: View {
    let scans: [ScanRecord]
    @Environment(\.kolaTheme) private var theme
    @State private var selectedDate: Date?

    private var points: [ScanRecord] { scans.sorted { $0.date < $1.date } }

    private var selectedScan: ScanRecord? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: Text("Health trend"), systemImage: "chart.xyaxis.line")
            if points.count < 2 {
                Text("Scan this plant a few times to see its recovery trend.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    // Severity bands for context.
                    if let first = points.first?.date, let last = points.last?.date {
                        RectangleMark(xStart: .value("From", first), xEnd: .value("To", last),
                                      yStart: .value("Low", 76), yEnd: .value("Top", 100))
                            .foregroundStyle(Color.green.opacity(0.07))
                        RectangleMark(xStart: .value("From", first), xEnd: .value("To", last),
                                      yStart: .value("Bottom", 0), yEnd: .value("Severe", 44))
                            .foregroundStyle(Color.red.opacity(0.07))
                    }

                    ForEach(points) { scan in
                        AreaMark(x: .value("Date", scan.date), y: .value("Health", scan.healthScore))
                            .foregroundStyle(LinearGradient(colors: [theme.accent.opacity(0.35), theme.accent.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Date", scan.date), y: .value("Health", scan.healthScore))
                            .foregroundStyle(theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", scan.date), y: .value("Health", scan.healthScore))
                            .foregroundStyle(scan.severity.color)
                            .symbolSize(60)
                    }

                    if let selectedScan {
                        RuleMark(x: .value("Selected", selectedScan.date))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                            .annotation(position: .top, alignment: .center) {
                                VStack(spacing: 2) {
                                    Text("\(selectedScan.healthScore)").font(.headline)
                                    Text(selectedScan.date, format: .dateTime.day().month())
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(6)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXSelection(value: $selectedDate)
                .frame(height: 200)
                .accessibilityLabel(Text("Health score over time"))
                .accessibilityValue(Text(points.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)): \($0.healthScore)" }
                    .joined(separator: ", ")))
            }
        }
        .cardStyle()
    }
}
