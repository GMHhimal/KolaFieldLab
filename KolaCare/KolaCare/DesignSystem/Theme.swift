//
//  Theme.swift
//  KolaCare
//
//  Brand colours and theming. Three palettes inspired by Sri Lankan landscapes
//  (paddy fields, tea estates, cinnamon gardens). Every colour has a light and a
//  dark variant tuned for WCAG AA contrast against the system backgrounds.
//

import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// A colour that adapts to Dark Mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

enum ThemePalette: String, CaseIterable, Identifiable {
    case paddy, tea, cinnamon

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .paddy: "Paddy green"
        case .tea: "Tea estate"
        case .cinnamon: "Cinnamon"
        }
    }

    var accent: Color {
        switch self {
        case .paddy: Color(light: 0x2E7D32, dark: 0x66BB6A)
        case .tea: Color(light: 0x00695C, dark: 0x4DB6AC)
        case .cinnamon: Color(light: 0x9A4A12, dark: 0xE0975A)
        }
    }

    var secondary: Color {
        switch self {
        case .paddy: Color(light: 0xF9A825, dark: 0xFFD54F)
        case .tea: Color(light: 0x6D4C41, dark: 0xBCAAA4)
        case .cinnamon: Color(light: 0x33691E, dark: 0x9CCC65)
        }
    }

    var heroGradient: LinearGradient {
        LinearGradient(colors: [accent, accent.opacity(0.65), secondary.opacity(0.55)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct KolaTheme {
    var palette: ThemePalette = .paddy

    var accent: Color { palette.accent }
    var secondary: Color { palette.secondary }
    var heroGradient: LinearGradient { palette.heroGradient }

    // Surfaces use semantic system colours so Dark Mode and Increase Contrast work automatically.
    let background = Color(uiColor: .systemGroupedBackground)
    let card = Color(uiColor: .secondarySystemGroupedBackground)
    let elevatedCard = Color(uiColor: .tertiarySystemGroupedBackground)
    let separator = Color(uiColor: .separator)

    static let cornerRadius: CGFloat = 20
    static let spacing: CGFloat = 16
}

private struct KolaThemeKey: EnvironmentKey {
    static let defaultValue = KolaTheme()
}

extension EnvironmentValues {
    var kolaTheme: KolaTheme {
        get { self[KolaThemeKey.self] }
        set { self[KolaThemeKey.self] = newValue }
    }
}
