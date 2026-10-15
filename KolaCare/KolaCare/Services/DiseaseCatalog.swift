//
//  DiseaseCatalog.swift
//  KolaCare
//
//  Read-only, in-memory index over the bundled disease catalogue.
//  Loaded once at launch (≈30 entries, a few KB) and shared app-wide.
//

import Foundation
import OSLog
import SwiftUI

final class DiseaseCatalog: @unchecked Sendable {
    static let shared = DiseaseCatalog(bundle: .main)

    let diseases: [Disease]
    private let byID: [String: Disease]
    private let byNormalisedLabel: [String: Disease]

    init(diseases: [Disease]) {
        self.diseases = diseases
        self.byID = Dictionary(diseases.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var labels: [String: Disease] = [:]
        for disease in diseases {
            for label in disease.modelLabels {
                labels[Self.normalise(label)] = disease
            }
        }
        self.byNormalisedLabel = labels
    }

    convenience init(bundle: Bundle) {
        self.init(diseases: Self.loadDiseases(from: bundle))
    }

    static func loadDiseases(from bundle: Bundle) -> [Disease] {
        guard let url = bundle.url(forResource: "diseases", withExtension: "json") else {
            Logger.diagnosis.fault("diseases.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(DiseaseCatalogFile.self, from: data).diseases
        } catch {
            Logger.diagnosis.fault("diseases.json failed to decode: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Lower-cases and strips everything except letters and digits so
    /// "Corn_(maize)___Common_rust_" and "corn maize common rust" match.
    static func normalise(_ label: String) -> String {
        String(label.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    // MARK: Lookup

    func disease(id: String) -> Disease? { byID[id] }

    func disease(forModelLabel label: String) -> Disease? { byNormalisedLabel[Self.normalise(label)] }

    func diseases(for crop: Crop) -> [Disease] { diseases.filter { $0.crop == crop } }

    /// Catalogue entries a user can browse (excludes generic colour-analysis results).
    var libraryEntries: [Disease] { diseases.filter { $0.crop != .other } }

    func search(_ text: String, crop: Crop? = nil, type: PathogenType? = nil) -> [Disease] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return libraryEntries.filter { disease in
            (crop == nil || disease.crop == crop)
            && (type == nil || disease.type == type)
            && (query.isEmpty
                || disease.name.localizedCaseInsensitiveContains(query)
                || disease.names.en.localizedCaseInsensitiveContains(query)
                || disease.pathogen.localizedCaseInsensitiveContains(query)
                || disease.symptoms.contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    /// Diseases worth checking the weather for, given the crops a user grows.
    func weatherSensitiveDiseases(for crops: Set<Crop>) -> [Disease] {
        diseases.filter { crops.contains($0.crop) && $0.riskProfile != nil }
    }
}

// MARK: - Environment injection

private struct DiseaseCatalogKey: EnvironmentKey {
    static let defaultValue = DiseaseCatalog.shared
}

extension EnvironmentValues {
    var diseaseCatalog: DiseaseCatalog {
        get { self[DiseaseCatalogKey.self] }
        set { self[DiseaseCatalogKey.self] = newValue }
    }
}
