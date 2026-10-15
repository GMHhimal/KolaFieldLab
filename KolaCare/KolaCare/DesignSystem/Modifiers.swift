//
//  Modifiers.swift
//  KolaCare
//
//  Custom view modifiers that give KolaCare a consistent look and motion language.
//

import SwiftUI

// MARK: - Card

/// Rounded, softly elevated container used for every dashboard and detail section.
struct CardModifier: ViewModifier {
    @Environment(\.kolaTheme) private var theme
    var padding: CGFloat = KolaTheme.spacing

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: KolaTheme.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

// MARK: - Shimmer (loading placeholder)

/// Animated highlight sweeping across redacted placeholders while data loads.
/// Disabled automatically when Reduce Motion is on.
struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content
                .redacted(reason: .placeholder)
                .overlay {
                    if !reduceMotion {
                        GeometryReader { proxy in
                            LinearGradient(colors: [.clear, .white.opacity(0.45), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: proxy.size.width * 0.6)
                                .offset(x: phase * proxy.size.width * 1.6)
                                .blendMode(.plusLighter)
                        }
                        .mask(content.redacted(reason: .placeholder))
                        .allowsHitTesting(false)
                    }
                }
                .onAppear {
                    withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
                }
                .accessibilityLabel(Text("Loading"))
        } else {
            content
        }
    }
}

// MARK: - Staggered entrance

/// Slides and fades content in with a per-index delay, producing a cascading reveal.
struct StaggeredAppear: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 24)
            .scaleEffect(visible || reduceMotion ? 1 : 0.97)
            .onAppear {
                guard !visible else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(reduceMotion ? 0 : Double(index) * 0.07)) {
                    visible = true
                }
            }
    }
}

// MARK: - Pressable button style

/// Springy scale-down on press with a light haptic — used for primary actions and cards.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Filled, full-width primary button.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.kolaTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal)
            .foregroundStyle(.white)
            .background(theme.accent.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Tinted secondary button.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.kolaTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 12)
            .foregroundStyle(theme.accent)
            .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - iOS 18 zoom navigation transition (graceful fallback on iOS 17)

struct ZoomTransitionSource: ViewModifier {
    let id: AnyHashable
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            if #available(iOS 18.0, *) {
                content.matchedTransitionSource(id: id, in: namespace)
            } else {
                content
            }
        } else {
            content
        }
    }
}

struct ZoomTransitionDestination: ViewModifier {
    let id: AnyHashable
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            if #available(iOS 18.0, *) {
                content.navigationTransition(.zoom(sourceID: id, in: namespace))
            } else {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Convenience

extension View {
    func cardStyle(padding: CGFloat = KolaTheme.spacing) -> some View { modifier(CardModifier(padding: padding)) }
    func shimmering(_ active: Bool) -> some View { modifier(ShimmerModifier(active: active)) }
    func staggeredAppear(index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
    func zoomSource(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        modifier(ZoomTransitionSource(id: AnyHashable(id), namespace: namespace))
    }
    func zoomDestination(id: some Hashable, in namespace: Namespace.ID?) -> some View {
        modifier(ZoomTransitionDestination(id: AnyHashable(id), namespace: namespace))
    }
}
