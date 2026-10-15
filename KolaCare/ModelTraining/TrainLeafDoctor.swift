// TrainLeafDoctor.swift
// Trains KolaCare's CoreML leaf-disease classifier with Create ML (transfer learning).
//
// Run on a Mac (macOS 14+, Xcode installed):
//   swift ModelTraining/TrainLeafDoctor.swift ~/Datasets/kolacare ~/Desktop/LeafDoctor.mlmodel
//
// Expected dataset layout (produced by prepare_dataset.py):
//   kolacare/train/<Label>/*.jpg
//   kolacare/test/<Label>/*.jpg
// Label folder names must match `modelLabels` in KolaCare/Resources/diseases.json
// (e.g. "Tomato___Early_blight"); matching ignores case and punctuation.

import CreateML
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    print("usage: swift TrainLeafDoctor.swift <dataset-dir> [output.mlmodel]")
    exit(1)
}

let datasetURL = URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath)
let outputURL = URL(fileURLWithPath: ((arguments.count > 2 ? arguments[2] : "LeafDoctor.mlmodel") as NSString).expandingTildeInPath)
let trainURL = datasetURL.appendingPathComponent("train")
let testURL = datasetURL.appendingPathComponent("test")

// Transfer learning on Apple's on-device Vision feature extractor keeps the model
// small (a few MB) and fast on the Neural Engine. Augmentation simulates real
// field photos (different framing, rotation, blur and lighting) so the model
// generalises beyond PlantVillage's uniform lab backgrounds.
let parameters = MLImageClassifier.ModelParameters(
    validation: .split(strategy: .automatic),
    maxIterations: 30,
    augmentation: [.crop, .rotation, .blur, .exposure, .flip],
    algorithm: .transferLearning(featureExtractor: .scenePrint(revision: 2), classifier: .logisticRegressor)
)

print("Training on \(trainURL.path)…")
let start = Date()
let classifier = try MLImageClassifier(trainingData: .labeledDirectories(at: trainURL), parameters: parameters)
print(String(format: "Trained in %.0f s", Date().timeIntervalSince(start)))
print(String(format: "Training accuracy:   %.2f%%", (1 - classifier.trainingMetrics.classificationError) * 100))
print(String(format: "Validation accuracy: %.2f%%", (1 - classifier.validationMetrics.classificationError) * 100))

if FileManager.default.fileExists(atPath: testURL.path) {
    let evaluation = classifier.evaluation(on: .labeledDirectories(at: testURL))
    print(String(format: "Test accuracy:       %.2f%%", (1 - evaluation.classificationError) * 100))
    print("Confusion matrix and per-class precision/recall:")
    print(evaluation.confusion)
    print(evaluation.precisionRecall)
}

let metadata = MLModelMetadata(author: "G M H Himal (IT23152632)",
                               shortDescription: "KolaCare leaf disease classifier for tomato, potato, chilli, maize and rice.",
                               license: "Trained on PlantVillage (CC BY-SA 4.0) and public rice leaf datasets.",
                               version: "1.0")
try classifier.write(to: outputURL, metadata: metadata)
print("Saved model to \(outputURL.path)")
print("Next: drag LeafDoctor.mlmodel into KolaCare/Resources in Xcode (target: KolaCare) and rebuild.")
