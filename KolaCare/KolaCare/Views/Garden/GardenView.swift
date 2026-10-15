//
//  GardenView.swift
//  KolaCare
//
//  The user's plants as an adaptive grid (2 columns on iPhone portrait, more on
//  iPad / landscape), with search, crop filter chips, sorting and context menus.
//

import SwiftData
import SwiftUI

enum GardenSort: String, CaseIterable, Identifiable {
    case recent, name, health

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .recent: "Recently added"
        case .name: "Name"
        case .health: "Needs attention first"
        }
    }
}

struct GardenView: View {
    @Query(sort: \Plant.createdAt, order: .reverse) private var plants: [Plant]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(\.kolaTheme) private var theme

    @Namespace private var zoomNamespace
    @State private var searchText = ""
    @State private var cropFilter: Crop?
    @State private var sort: GardenSort = .recent
    @State private var showingAddPlant = false
    @State private var plantToEdit: Plant?
    @State private var plantToDelete: Plant?

    private var filtered: [Plant] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matches = plants.filter { plant in
            (cropFilter == nil || plant.crop == cropFilter)
            && (query.isEmpty || plant.name.localizedCaseInsensitiveContains(query)
                || plant.plotName.localizedCaseInsensitiveContains(query))
        }
        switch sort {
        case .recent: return matches
        case .name: return matches.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .health: return matches.sorted { ($0.healthScore ?? 101) < ($1.healthScore ?? 101) }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 14)]

    var body: some View {
        Group {
            if plants.isEmpty {
                emptyState
            } else {
                ScrollView {
                    filterBar
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filtered) { plant in
                            NavigationLink(value: plant) {
                                PlantCard(plant: plant)
                                    .zoomSource(id: plant.id, in: zoomNamespace)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .contextMenu { contextMenu(for: plant) } preview: {
                                PlantCard(plant: plant).frame(width: 260)
                            }
                            .accessibilityIdentifier("garden.plant.\(plant.name)")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                    .animation(.spring(response: 0.45, dampingFraction: 0.85), value: filtered.map(\.id))

                    if filtered.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .searchable(text: $searchText, prompt: Text("Search plants or plots"))
            }
        }
        .background(theme.background)
        .navigationTitle(Text("My garden"))
        .appNavigationDestinations(zoomNamespace: zoomNamespace)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker(selection: $sort) {
                        ForEach(GardenSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    } label: {
                        Text("Sort by")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }
                .accessibilityLabel(Text("Sort"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddPlant = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel(Text("Add plant"))
                .accessibilityIdentifier("garden.add")
            }
        }
        .sheet(isPresented: $showingAddPlant) {
            NavigationStack { AddPlantView() }
        }
        .sheet(item: $plantToEdit) { plant in
            NavigationStack { AddPlantView(editing: plant) }
        }
        .confirmationDialog(Text("Delete this plant?"), isPresented: Binding(
            get: { plantToDelete != nil },
            set: { if !$0 { plantToDelete = nil } }), titleVisibility: .visible) {
            Button("Delete plant and its scans", role: .destructive) {
                if let plantToDelete {
                    withAnimation { GardenRepository(context: modelContext).delete(plantToDelete) }
                }
                plantToDelete = nil
            }
        } message: {
            Text("This permanently removes the plant and all of its scan history.")
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: Text("All"), isSelected: cropFilter == nil) {
                    withAnimation { cropFilter = nil }
                }
                ForEach(Crop.allCases) { crop in
                    if plants.contains(where: { $0.crop == crop }) {
                        FilterChip(title: Text(crop.displayName), leading: crop.emoji, isSelected: cropFilter == crop) {
                            withAnimation { cropFilter = cropFilter == crop ? nil : crop }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .sensoryFeedback(.selection, trigger: cropFilter)
    }

    @ViewBuilder
    private func contextMenu(for plant: Plant) -> some View {
        Button {
            router.startScan(for: plant.id)
        } label: {
            Label("Scan this plant", systemImage: "viewfinder")
        }
        Button {
            plantToEdit = plant
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Divider()
        Button(role: .destructive) {
            plantToDelete = plant
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your garden is empty", systemImage: "leaf")
        } description: {
            Text("Add the plants, beds or paddy plots you want to monitor, or explore with a demo garden.")
        } actions: {
            Button("Add a plant") { showingAddPlant = true }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("garden.empty.add")
            Button("Load demo garden") {
                withAnimation { DemoDataSeeder.seed(into: modelContext) }
            }
            .accessibilityIdentifier("garden.empty.demo")
        }
    }
}

// MARK: - Plant card

struct PlantCard: View {
    let plant: Plant
    @Environment(\.kolaTheme) private var theme
    @Environment(\.diseaseCatalog) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlantThumbnail(data: plant.displayImageData, crop: plant.crop, cornerRadius: 14)
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topTrailing) {
                    HealthRing(score: plant.healthScore, lineWidth: 4, showsLabel: false)
                        .frame(width: 28, height: 28)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(plant.plotName.isEmpty ? String(localized: plant.crop.displayName) : plant.plotName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let scan = plant.latestScan {
                    HStack(spacing: 6) {
                        SeverityBadge(severity: scan.severity, compact: true)
                        Text(catalog.disease(id: scan.diseaseID)?.name ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Not scanned yet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityValue(plant.healthScore.map { Text("Health \($0) out of 100") } ?? Text("Not scanned yet"))
    }
}

// MARK: - Scan row

struct ScanRow: View {
    let scan: ScanRecord
    var showsPlantName = false
    @Environment(\.diseaseCatalog) private var catalog

    var body: some View {
        HStack(spacing: 12) {
            PlantThumbnail(data: scan.thumbnailData, crop: scan.plant?.crop ?? .other, cornerRadius: 10)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(catalog.disease(id: scan.diseaseID)?.name ?? scan.diseaseID)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if showsPlantName, let name = scan.plant?.name {
                        Text(name)
                        Text("·")
                    }
                    Text(scan.date, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            SeverityBadge(severity: scan.severity, compact: true)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
