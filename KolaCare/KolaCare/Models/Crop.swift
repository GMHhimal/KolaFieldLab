//
//  Crop.swift
//  KolaCare
//
//  Crops supported by KolaCare. Chosen for their importance to Sri Lankan
//  smallholders and home gardeners and for the availability of public
//  leaf-image datasets used to train the CoreML model.
//

import SwiftUI

enum Crop: String, Codable, CaseIterable, Identifiable, Sendable {
    case tomato, potato, chilli, corn, rice, other

    var id: String { rawValue }

    /// Localised display name (keys live in Localizable.xcstrings).
    var displayName: LocalizedStringResource {
        switch self {
        case .tomato: "Tomato"
        case .potato: "Potato"
        case .chilli: "Chilli"
        case .corn: "Maize"
        case .rice: "Paddy"
        case .other: "Other"
        }
    }

    /// Emoji gives a friendly, instantly recognisable crop marker that also
    /// works for users with low literacy.
    var emoji: String {
        switch self {
        case .tomato: "🍅"
        case .potato: "🥔"
        case .chilli: "🌶️"
        case .corn: "🌽"
        case .rice: "🌾"
        case .other: "🌿"
        }
    }

    /// Crops a user can add to their garden (excludes the catch-all "other" in pickers that need a real crop).
    static var plantable: [Crop] { [.tomato, .potato, .chilli, .corn, .rice, .other] }
}
