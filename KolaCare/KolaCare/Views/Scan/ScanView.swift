//
//  ScanView.swift
//  KolaCare
//
//  Capture screen: take a photo, pick one from the library, or try a bundled
//  sample leaf (useful in the Simulator). Shows a live "scanning" animation
//  while the on-device pipeline runs, then pushes the diagnosis.
//

import PhotosUI
import SwiftData
import SwiftUI
import TipKit

struct ScanTip: Tip {
    var title: Text { Text("Get an accurate diagnosis") }
    var message: Text? { Text("Fill the frame with one leaf, in daylight, against a plain background.") }
    var image: Image? { Image(systemName: "lightbulb.max") }
}

struct ScanView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.kolaTheme) private var theme
    @Query(sort: \Plant.name) private var plants: [Plant]

    @State private var viewModel = ScanViewModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingResult = false
    @State private var showingError = false

    private let scanTip = ScanTip()
    private let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)

    private var targetPlant: Plant? {
        guard let id = router.scanTargetPlantID else { return nil }
        return plants.first { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let targetPlant {
                    HStack {
                        TagChip(text: Text("Scanning for \(targetPlant.name)"), systemImage: "target", tint: theme.accent)
                        Spacer()
                        Button {
                            router.scanTargetPlantID = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel(Text("Clear plant"))
                    }
                }

                viewfinder
                    .frame(maxWidth: 520)

                if viewModel.isAnalyzing {
                    AnalysisProgressView(step: viewModel.analysisStep)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    actions
                        .transition(.opacity)
                }

                guidance
            }
            .padding()
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: viewModel.isAnalyzing)
        }
        .background(theme.background)
        .navigationTitle(Text("Scan a leaf"))
        .navigationDestination(isPresented: $showingResult) {
            DiagnosisResultView(viewModel: viewModel, preselectedPlantID: router.scanTargetPlantID) {
                showingResult = false
                router.scanTargetPlantID = nil
            }
        }
        .onChange(of: showingResult) { _, showing in
            // Reset only after the result screen has been popped (Done button or back swipe).
            if !showing { viewModel.reset() }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in
                showingCamera = false
                if let image { viewModel.analyze(uiImage: image) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    viewModel.analyze(imageData: data)
                } else {
                    viewModel.analyze(imageData: Data())
                }
                pickerItem = nil
            }
        }
        .onChange(of: viewModel.phase) { _, phase in
            switch phase {
            case .result: showingResult = true
            case .failed: showingError = true
            default: break
            }
        }
        .alert(Text("Couldn't analyse the photo"), isPresented: $showingError) {
            Button("OK") { viewModel.reset() }
        } message: {
            if case .failed(let message) = viewModel.phase { Text(message) }
        }
        .sensoryFeedback(.success, trigger: viewModel.phase == .result)
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.card)

            if let image = viewModel.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        if viewModel.isAnalyzing { ScanningOverlay() }
                    }
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .accessibilityLabel(Text("Selected leaf photo"))
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(theme.accent.gradient)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Place one leaf inside the frame")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .accessibilityElement(children: .combine)
            }

            ViewfinderCorners()
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .padding(14)
                .accessibilityHidden(true)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: viewModel.image)
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 12) {
            TipView(scanTip, arrowEdge: .bottom)

            if cameraAvailable {
                Button {
                    scanTip.invalidate(reason: .actionPerformed)
                    showingCamera = true
                } label: {
                    Label("Take photo", systemImage: "camera.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("scan.camera")
            }

            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label("Photo library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(cameraAvailable ? AnyButtonStyle(SecondaryButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
                .simultaneousGesture(TapGesture().onEnded { scanTip.invalidate(reason: .actionPerformed) })
                .accessibilityIdentifier("scan.library")

                Menu {
                    Button { analyzeSample("SampleLeafHealthy") } label: { Label("Healthy leaf", systemImage: "leaf") }
                    Button { analyzeSample("SampleLeafSpotted") } label: { Label("Spotted leaf", systemImage: "circle.dotted") }
                    Button { analyzeSample("SampleLeafYellowing") } label: { Label("Yellowing leaf", systemImage: "sun.haze") }
                } label: {
                    Label("Try a sample", systemImage: "sparkles")
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("scan.sample")
            }
        }
    }

    private func analyzeSample(_ name: String) {
        guard let image = UIImage(named: name)?.cgImage else { return }
        scanTip.invalidate(reason: .actionPerformed)
        viewModel.analyze(cgImage: image)
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: Text("For the best result"), systemImage: "checklist")
            GuidanceRow(symbol: "sun.max", text: Text("Shoot in daylight or bright shade — avoid flash."))
            GuidanceRow(symbol: "hand.raised", text: Text("Hold the leaf flat; include both healthy and damaged parts."))
            GuidanceRow(symbol: "square.dashed", text: Text("Use a plain background like paper or your palm."))
            GuidanceRow(symbol: "lock.shield", text: Text("Photos are analysed on your phone and never uploaded."))
        }
        .cardStyle()
    }
}

private struct GuidanceRow: View {
    let symbol: String
    let text: Text

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            text.font(.subheadline)
        }
    }
}

/// Type-erased button style for switching styles at runtime.
struct AnyButtonStyle: ButtonStyle {
    private let make: (ButtonStyleConfiguration) -> AnyView

    init<S: ButtonStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: ButtonStyleConfiguration) -> some View { make(configuration) }
}
