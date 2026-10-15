//
//  FieldMapView.swift
//  KolaCare
//
//  MapKit field map: every geotagged plant is a health-coloured annotation, and
//  diseased plants get a "spread zone" circle sized by how contagious the disease
//  is — helping farmers see which neighbouring plots to check next.
//

import MapKit
import SwiftData
import SwiftUI

struct FieldMapView: View {
    @Query private var plants: [Plant]
    @Environment(\.diseaseCatalog) private var catalog
    @Environment(\.kolaTheme) private var theme
    @Environment(AppRouter.self) private var router
    @Environment(LocationProvider.self) private var locationProvider

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedPlant: Plant?
    @State private var useSatellite = true
    @State private var showsSpreadZones = true

    private var mappedPlants: [Plant] { plants.filter { $0.coordinate != nil } }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()

            ForEach(mappedPlants) { plant in
                if let coordinate = plant.coordinate {
                    if showsSpreadZones, let radius = spreadRadius(for: plant) {
                        MapCircle(center: coordinate, radius: radius)
                            .stroke((plant.severity?.color ?? .orange).opacity(0.7), lineWidth: 1.5)
                            .foregroundStyle((plant.severity?.color ?? .orange).opacity(0.18))
                    }
                    Annotation(plant.name, coordinate: coordinate, anchor: .bottom) {
                        PlantMapPin(plant: plant, isSelected: selectedPlant?.id == plant.id)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selectedPlant = plant }
                            }
                    }
                }
            }
        }
        .mapStyle(useSatellite ? .hybrid(elevation: .realistic) : .standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
            MapPitchToggle()
        }
        .overlay(alignment: .top) {
            if mappedPlants.isEmpty {
                Label("Add a location to your plants to see them here.", systemImage: "mappin.slash")
                    .font(.subheadline)
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let selectedPlant {
                SelectedPlantCard(plant: selectedPlant,
                                  diseaseName: selectedPlant.latestScan.flatMap { catalog.disease(id: $0.diseaseID)?.name },
                                  onOpen: { router.openPlant(selectedPlant) },
                                  onScan: { router.startScan(for: selectedPlant.id) },
                                  onClose: { withAnimation { self.selectedPlant = nil } })
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle(Text("Field map"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Toggle(isOn: $useSatellite.animation()) { Label("Satellite", systemImage: "globe.asia.australia") }
                    Toggle(isOn: $showsSpreadZones.animation()) { Label("Spread zones", systemImage: "circle.dashed") }
                    Button {
                        withAnimation { position = .automatic }
                    } label: {
                        Label("Show all plants", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                    }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                }
                .accessibilityLabel(Text("Map options"))
            }
        }
        .onAppear { locationProvider.requestPermission() }
    }

    /// Larger circles for more contagious diseases and worse severity.
    private func spreadRadius(for plant: Plant) -> CLLocationDistance? {
        guard let scan = plant.latestScan,
              let disease = catalog.disease(id: scan.diseaseID),
              !disease.isHealthy, disease.contagiousness > 0 else { return nil }
        return Double(disease.contagiousness) * 40 * (1 + scan.affectedArea * 2)
    }
}

private struct PlantMapPin: View {
    let plant: Plant
    let isSelected: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var color: Color { plant.severity?.color ?? .gray }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if plant.severity == .severe && !reduceMotion {
                    Circle()
                        .fill(color.opacity(0.35))
                        .frame(width: 54, height: 54)
                        .scaleEffect(pulse ? 1.3 : 0.8)
                        .opacity(pulse ? 0 : 1)
                }
                Circle()
                    .fill(.background)
                    .frame(width: isSelected ? 48 : 38, height: isSelected ? 48 : 38)
                    .overlay { Circle().strokeBorder(color, lineWidth: 4) }
                    .shadow(radius: 3, y: 2)
                Text(plant.crop.emoji).font(isSelected ? .title2 : .title3)
            }
            Image(systemName: "triangle.fill")
                .font(.caption2)
                .foregroundStyle(color)
                .rotationEffect(.degrees(180))
                .offset(y: -3)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        .onAppear {
            guard plant.severity == .severe, !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(plant.name))
        .accessibilityValue(plant.severity.map { Text($0.title) } ?? Text("Not scanned yet"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct SelectedPlantCard: View {
    let plant: Plant
    let diseaseName: String?
    var onOpen: () -> Void
    var onScan: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PlantThumbnail(data: plant.displayImageData, crop: plant.crop, cornerRadius: 12)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name).font(.headline)
                if let diseaseName {
                    Text(diseaseName).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open", action: onOpen).buttonStyle(.borderedProminent)
                    Button(action: onScan) { Label("Scan", systemImage: "viewfinder") }.buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
            Spacer()
            HealthRing(score: plant.healthScore, lineWidth: 6)
                .frame(width: 56, height: 56)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
            .accessibilityLabel(Text("Close"))
        }
    }
}
