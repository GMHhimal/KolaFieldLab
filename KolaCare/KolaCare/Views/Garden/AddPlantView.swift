//
//  AddPlantView.swift
//  KolaCare
//
//  Create or edit a plant. Location can come from GPS or from tapping on a
//  satellite map (MapReader converts the tap into a coordinate).
//

import MapKit
import PhotosUI
import SwiftData
import SwiftUI

struct AddPlantView: View {
    private let editing: Plant?
    private let onSave: ((Plant) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationProvider.self) private var locationProvider

    @State private var name: String
    @State private var crop: Crop
    @State private var plotName: String
    @State private var notes: String
    @State private var hasPlantedDate: Bool
    @State private var plantedOn: Date
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var photoData: Data?
    @State private var photoItem: PhotosPickerItem?
    @State private var mapPosition: MapCameraPosition
    @State private var locating = false
    @FocusState private var nameFocused: Bool

    /// New plant.
    init(initialCrop: Crop? = nil, onSave: ((Plant) -> Void)? = nil) {
        self.editing = nil
        self.onSave = onSave
        _name = State(initialValue: "")
        _crop = State(initialValue: (initialCrop == .other ? nil : initialCrop) ?? .tomato)
        _plotName = State(initialValue: "")
        _notes = State(initialValue: "")
        _hasPlantedDate = State(initialValue: false)
        _plantedOn = State(initialValue: .now)
        _coordinate = State(initialValue: nil)
        _photoData = State(initialValue: nil)
        _mapPosition = State(initialValue: .region(MKCoordinateRegion(center: LocationProvider.fallbackCoordinate,
                                                                      latitudinalMeters: 300_000, longitudinalMeters: 300_000)))
    }

    /// Edit an existing plant.
    init(editing plant: Plant) {
        self.editing = plant
        self.onSave = nil
        _name = State(initialValue: plant.name)
        _crop = State(initialValue: plant.crop)
        _plotName = State(initialValue: plant.plotName)
        _notes = State(initialValue: plant.notes)
        _hasPlantedDate = State(initialValue: plant.plantedOn != nil)
        _plantedOn = State(initialValue: plant.plantedOn ?? .now)
        _coordinate = State(initialValue: plant.coordinate)
        _photoData = State(initialValue: plant.photoData)
        let center = plant.coordinate ?? LocationProvider.fallbackCoordinate
        _mapPosition = State(initialValue: .region(MKCoordinateRegion(center: center,
                                                                      latitudinalMeters: plant.coordinate == nil ? 300_000 : 800,
                                                                      longitudinalMeters: plant.coordinate == nil ? 300_000 : 800)))
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                TextField("Name, e.g. Tomato bed A", text: $name)
                    .focused($nameFocused)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityIdentifier("addPlant.name")
                TextField("Plot or location name", text: $plotName)
                    .accessibilityIdentifier("addPlant.plot")
            } header: {
                Text("Plant")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Crop.plantable) { option in
                            FilterChip(title: Text(option.displayName), leading: option.emoji, isSelected: crop == option) {
                                withAnimation(.snappy) { crop = option }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                Toggle("Record planting date", isOn: $hasPlantedDate.animation())
                if hasPlantedDate {
                    DatePicker("Planted on", selection: $plantedOn, in: ...Date.now, displayedComponents: .date)
                }
            } header: {
                Text("Crop")
            }

            Section {
                HStack {
                    PlantThumbnail(data: photoData, crop: crop, cornerRadius: 12)
                        .frame(width: 64, height: 64)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(photoData == nil ? LocalizedStringKey("Add photo") : LocalizedStringKey("Change photo"),
                              systemImage: "photo")
                    }
                    if photoData != nil {
                        Spacer()
                        Button(role: .destructive) {
                            withAnimation { photoData = nil }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text("Remove photo"))
                    }
                }
            } header: {
                Text("Photo")
            }

            Section {
                locationMap
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
                HStack {
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        if locating {
                            ProgressView()
                        } else {
                            Label("Use my location", systemImage: "location.fill")
                        }
                    }
                    .disabled(locating)
                    Spacer()
                    if coordinate != nil {
                        Button("Clear", role: .destructive) { withAnimation { coordinate = nil } }
                            .buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Tap the map to drop a pin on your plot. Locations power the field map and local weather alerts.")
            }

            Section {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            } header: {
                Text("Notes")
            }
        }
        .navigationTitle(editing == nil ? Text("New plant") : Text("Edit plant"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(trimmedName.isEmpty)
                    .accessibilityIdentifier("addPlant.save")
            }
        }
        .onAppear { if editing == nil { nameFocused = true } }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = ImageProcessing.downsample(data, maxPixelSize: 900) {
                    withAnimation { photoData = ImageProcessing.jpegData(from: image, quality: 0.75) }
                }
                photoItem = nil
            }
        }
    }

    private var locationMap: some View {
        MapReader { proxy in
            Map(position: $mapPosition) {
                if let coordinate {
                    Marker(String(localized: "Plot"), systemImage: "leaf.fill", coordinate: coordinate)
                        .tint(.green)
                }
                UserAnnotation()
            }
            .mapStyle(.hybrid(elevation: .flat))
            .onTapGesture { point in
                if let tapped = proxy.convert(point, from: .local) {
                    withAnimation(.snappy) { coordinate = tapped }
                }
            }
            .accessibilityLabel(Text("Map. Tap to set the plot location."))
        }
    }

    private func useCurrentLocation() async {
        locating = true
        defer { locating = false }
        guard let location = await locationProvider.currentLocation() else { return }
        withAnimation {
            coordinate = location.coordinate
            mapPosition = .region(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        if let plant = editing {
            plant.name = trimmedName
            plant.crop = crop
            plant.plotName = plotName
            plant.notes = notes
            plant.plantedOn = hasPlantedDate ? plantedOn : nil
            plant.coordinate = coordinate
            plant.photoData = photoData
            GardenRepository(context: modelContext).save()
        } else {
            let plant = GardenRepository(context: modelContext).addPlant(
                name: trimmedName, crop: crop, plotName: plotName, notes: notes,
                plantedOn: hasPlantedDate ? plantedOn : nil,
                latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                photoData: photoData)
            onSave?(plant)
        }
        dismiss()
    }
}
