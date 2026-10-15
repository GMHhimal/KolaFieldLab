//
//  LeafDiagnosisService.swift
//  KolaCare
//
//  The on-device diagnosis pipeline:
//
//    photo ─► 1. Vision subject lifting (iOS 17)  — isolates the leaf from soil/background
//          ─► 2. LeafPixelAnalyzer                — measures % yellow / dead tissue (severity)
//          ─► 3. CoreML classifier via Vision     — names the disease (if LeafDoctor.mlmodel is bundled)
//          ─► 4. Fallback heuristic               — generic diagnosis from colour metrics
//
//  Everything runs on the device: photos never leave the phone, and it works
//  offline in the field where mobile data is patchy.
//

import CoreImage
import CoreML
import OSLog
import Vision

// MARK: - Protocols (enable dependency injection and unit testing)

protocol LeafDiagnosing: Sendable {
    func diagnose(_ image: CGImage) async throws -> DiagnosisResult
}

struct LabelScore: Equatable, Sendable {
    let label: String
    let confidence: Double
}

protocol LeafClassifying: Sendable {
    var modelName: String { get }
    func classify(_ image: CGImage) throws -> [LabelScore]
}

enum DiagnosisError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        String(localized: "This photo couldn't be read. Please try another one.")
    }
}

// MARK: - CoreML classifier

/// Wraps a compiled Create ML image classifier. The model is optional at build time:
/// drop `LeafDoctor.mlmodel` into the KolaCare/Resources folder (see ModelTraining/README.md)
/// and Xcode compiles it into the bundle as `LeafDoctor.mlmodelc`.
final class CoreMLLeafClassifier: LeafClassifying, @unchecked Sendable {
    let modelName: String
    private let model: VNCoreMLModel

    init(model: VNCoreMLModel, name: String) {
        self.model = model
        self.modelName = name
    }

    static func loadBundled(named name: String = "LeafDoctor", bundle: Bundle = .main) -> CoreMLLeafClassifier? {
        guard let url = bundle.url(forResource: name, withExtension: "mlmodelc") else {
            Logger.diagnosis.info("No bundled \(name, privacy: .public).mlmodelc – using colour analysis only")
            return nil
        }
        do {
            let configuration = MLModelConfiguration()
            #if targetEnvironment(simulator)
            configuration.computeUnits = .cpuOnly       // the Simulator has no Neural Engine
            #else
            configuration.computeUnits = .all
            #endif
            let mlModel = try MLModel(contentsOf: url, configuration: configuration)
            return CoreMLLeafClassifier(model: try VNCoreMLModel(for: mlModel), name: name)
        } catch {
            Logger.diagnosis.error("Failed to load model: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func classify(_ image: CGImage) throws -> [LabelScore] {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        let observations = (request.results as? [VNClassificationObservation]) ?? []
        return observations
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
            .map { LabelScore(label: $0.identifier, confidence: Double($0.confidence)) }
    }
}

// MARK: - Subject lifting

enum LeafSegmenter {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Returns the image with the background made transparent, or `nil` when
    /// segmentation is unavailable (Simulator, older devices) or finds no subject.
    static func isolateLeaf(in image: CGImage) -> CGImage? {
        #if targetEnvironment(simulator)
        return nil
        #else
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances,
                                                             from: handler,
                                                             croppedToInstancesExtent: false)
            let ciImage = CIImage(cvPixelBuffer: buffer)
            return ciContext.createCGImage(ciImage, from: ciImage.extent)
        } catch {
            Logger.diagnosis.info("Segmentation unavailable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        #endif
    }
}

// MARK: - Pipeline

final class LeafDiagnosisService: LeafDiagnosing, @unchecked Sendable {
    /// Shared instance so the CoreML model is compiled and loaded only once per launch.
    /// (SwiftUI re-runs `@State` initial-value expressions on every view init, so
    /// creating the service there would reload the model repeatedly.)
    static let shared = LeafDiagnosisService()

    /// Below this the result is shown with a "not sure" warning.
    static let confidenceThreshold = 0.45

    private let catalog: DiseaseCatalog
    private let classifier: LeafClassifying?
    private let segmentationEnabled: Bool

    init(catalog: DiseaseCatalog = .shared,
         classifier: LeafClassifying? = CoreMLLeafClassifier.loadBundled(),
         segmentationEnabled: Bool = true) {
        self.catalog = catalog
        self.classifier = classifier
        self.segmentationEnabled = segmentationEnabled
    }

    var activeEngine: DiagnosisEngine { classifier == nil ? .colourAnalysis : .coreML }
    var modelName: String? { classifier?.modelName }

    func diagnose(_ image: CGImage) async throws -> DiagnosisResult {
        let signpostID = Signposts.diagnosis.makeSignpostID()
        let state = Signposts.diagnosis.beginInterval("Diagnose leaf", id: signpostID)
        defer { Signposts.diagnosis.endInterval("Diagnose leaf", state) }

        guard image.width > 16, image.height > 16 else { throw DiagnosisError.unreadableImage }

        // 1–2. Isolate the leaf, then measure symptoms.
        let isolated = segmentationEnabled ? LeafSegmenter.isolateLeaf(in: image) : nil
        let analysis = LeafPixelAnalyzer.analyze(isolated ?? image, usedSegmentation: isolated != nil)
        try Task.checkCancellation()

        // 3. Name the disease with the CoreML model when available.
        var predictions: [Prediction] = []
        var engine = DiagnosisEngine.colourAnalysis
        if let classifier {
            do {
                predictions = try classifier.classify(image)
                    .compactMap { score in
                        catalog.disease(forModelLabel: score.label).map { Prediction(diseaseID: $0.id, confidence: score.confidence) }
                    }
                    .uniqued(by: \.diseaseID)
                    .prefix(3)
                    .map { $0 }
                if !predictions.isEmpty { engine = .coreML }
            } catch {
                Logger.diagnosis.error("Classification failed, falling back: \(error.localizedDescription, privacy: .public)")
            }
        }

        // 4. Fallback.
        if predictions.isEmpty {
            predictions = [LeafPixelAnalyzer.heuristicDiagnosis(for: analysis.metrics)]
        }

        let top = predictions[0]
        return DiagnosisResult(diseaseID: top.diseaseID,
                               confidence: top.confidence,
                               predictions: predictions,
                               metrics: analysis.metrics,
                               engine: engine,
                               warnings: Self.qualityWarnings(metrics: analysis.metrics, confidence: top.confidence, engine: engine),
                               lesionMap: analysis.lesionMap)
    }

    static func qualityWarnings(metrics: LeafMetrics, confidence: Double, engine: DiagnosisEngine) -> [QualityWarning] {
        var warnings: [QualityWarning] = []
        if metrics.leafCoverage < 0.12 { warnings.append(.noLeafDetected) }
        if metrics.meanLuminance < 0.18 { warnings.append(.tooDark) }
        if metrics.meanLuminance > 0.88 { warnings.append(.tooBright) }
        if engine == .coreML && confidence < confidenceThreshold { warnings.append(.lowConfidence) }
        return warnings
    }
}

extension Sequence {
    /// Keeps the first element for each key, preserving order.
    func uniqued<Key: Hashable>(by key: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: key]).inserted }
    }
}
