//
//  ScanningOverlay.swift
//  KolaCare
//
//  Animated "laser" sweep and grid shown over the photo while it is analysed,
//  plus the step-by-step progress list. Reduce Motion swaps the sweep for a
//  gentle pulse.
//

import SwiftUI

struct ScanningOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.kolaTheme) private var theme
    @State private var sweep = false
    @State private var glow = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.opacity(0.25)

                GridPattern(spacing: 28)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)

                if reduceMotion {
                    theme.accent.opacity(glow ? 0.25 : 0.05)
                } else {
                    LinearGradient(colors: [.clear, theme.secondary.opacity(0.55), .white, theme.secondary.opacity(0.55), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                        .blendMode(.screen)
                        .offset(y: sweep ? proxy.size.height - 35 : -35)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .allowsHitTesting(false)
        .onAppear {
            if reduceMotion {
                withAnimation(.easeInOut(duration: 1.2).repeatForever()) { glow = true }
            } else {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { sweep = true }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct GridPattern: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        var y = rect.minY
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }
        return path
    }
}

/// The three pipeline stages with a spinner, checkmarks and an accessible progress value.
struct AnalysisProgressView: View {
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(ScanViewModel.analysisSteps.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 12) {
                    ZStack {
                        if index < step {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        } else if index == step {
                            ProgressView()
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 24, height: 24)
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(index <= step ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: step)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Analysing leaf"))
        .accessibilityValue(Text(ScanViewModel.analysisSteps[min(step, ScanViewModel.analysisSteps.count - 1)]))
        .accessibilityIdentifier("scan.progress")
    }
}
