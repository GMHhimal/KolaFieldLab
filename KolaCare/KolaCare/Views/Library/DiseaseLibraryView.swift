//
//  DiseaseLibraryView.swift
//  KolaCare
//
//  Searchable, filterable encyclopedia of the diseases and pests KolaCare knows.
//  Works fully offline from the bundled catalogue.
//

import SwiftUI

struct DiseaseLibraryView: View {
    @Environment(\.diseaseCatalog) private var catalog
    @Environment(\.kolaTheme) private var theme
    @State private var searchText = ""
    @State private var crop: Crop?
    @State private var type: PathogenType?

    private var results: [Disease] { catalog.search(searchText, crop: crop, type: type) }

    private var grouped: [(Crop, [Disease])] {
        let groups = Dictionary(grouping: results, by: \.crop)
        return Crop.allCases.compactMap { crop in
            guard let items = groups[crop], !items.isEmpty else { return nil }
            return (crop, items.sorted { ($0.isHealthy ? 1 : 0, $0.name) < ($1.isHealthy ? 1 : 0, $1.name) })
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: Text("All crops"), isSelected: crop == nil) { withAnimation { crop = nil } }
                        ForEach(Crop.allCases.filter { $0 != .other }) { option in
                            FilterChip(title: Text(option.displayName), leading: option.emoji, isSelected: crop == option) {
                                withAnimation { crop = crop == option ? nil : option }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(Color.clear)
            }

            ForEach(grouped, id: \.0) { crop, diseases in
                Section {
                    ForEach(diseases) { disease in
                        NavigationLink(value: disease) {
                            DiseaseRow(disease: disease)
                        }
                        .accessibilityIdentifier("library.disease.\(disease.id)")
                    }
                } header: {
                    Text("\(crop.emoji) \(Text(crop.displayName))")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .animation(.default, value: results.map(\.id))
        .searchable(text: $searchText, prompt: Text("Search diseases, symptoms, pathogens"))
        .navigationTitle(Text("Disease library"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $type) {
                        Text("All types").tag(PathogenType?.none)
                        ForEach(PathogenType.allCases.filter { $0 != .healthy }, id: \.self) { option in
                            Label { Text(option.title) } icon: { Image(systemName: option.symbol) }
                                .tag(Optional(option))
                        }
                    } label: {
                        Text("Type")
                    }
                } label: {
                    Image(systemName: type == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(Text("Filter by type"))
            }
        }
    }
}

private struct DiseaseRow: View {
    let disease: Disease

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: disease.type.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(disease.type.tint)
                .frame(width: 36, height: 36)
                .background(disease.type.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(disease.name).font(.body.weight(.medium))
                Text(disease.type.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if disease.contagiousness > 0 {
                ContagiousnessMeter(level: disease.contagiousness)
            }
        }
        .padding(.vertical, 2)
    }
}
