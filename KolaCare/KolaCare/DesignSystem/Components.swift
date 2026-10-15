//
//  Components.swift
//  KolaCare
//
//  Reusable custom SwiftUI components.
//

import SwiftUI

// MARK: - HealthRing

/// Animated circular gauge showing a 0–100 health score, coloured by severity.
/// Scales with Dynamic Type and reads naturally in VoiceOver.
struct HealthRing: View {
    let score: Int?
    var lineWidth: CGFloat = 10
    var showsLabel = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    private var progress: Double { Double(score ?? 0) / 100 }
    private var color: Color { score.map { HealthScore.severity(for: $0).color } ?? .secondary }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(AngularGradient(colors: [color.opacity(0.7), color], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsLabel {
                VStack(spacing: 0) {
                    Text(score.map { "\($0)" } ?? "–")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.5)
                    Text("health")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(lineWidth)
            }
        }
        .onAppear { animate(to: progress) }
        .onChange(of: score) { animate(to: progress) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Health score"))
        .accessibilityValue(score.map { Text("\($0) out of 100") } ?? Text("Not scanned yet"))
    }

    private func animate(to value: Double) {
        if reduceMotion {
            animatedProgress = value
        } else {
            withAnimation(.spring(response: 1.0, dampingFraction: 0.85)) { animatedProgress = value }
        }
    }
}

// MARK: - SeverityBadge

struct SeverityBadge: View {
    let severity: Severity
    var compact = false

    var body: some View {
        Label {
            Text(severity.title)
        } icon: {
            Image(systemName: severity.symbol)
        }
        .labelStyle(compact ? AnyLabelStyle(.iconOnly) : AnyLabelStyle(.titleAndIcon))
        .font(.caption.weight(.semibold))
        .padding(.horizontal, compact ? 6 : 10)
        .padding(.vertical, 5)
        .foregroundStyle(severity == .low ? Color.primary : severity.color)
        .background(severity.color.opacity(0.18), in: Capsule())
        .accessibilityLabel(Text("Severity: \(Text(severity.title))"))
    }
}

/// Type-erased label style so a view can switch styles at runtime.
struct AnyLabelStyle: LabelStyle {
    private let make: (LabelStyleConfiguration) -> AnyView

    init<S: LabelStyle>(_ style: S) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: LabelStyleConfiguration) -> some View { make(configuration) }
}

// MARK: - Chips

struct TagChip: View {
    let text: Text
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        Label { text } icon: { Image(systemName: systemImage) }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(tint)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Selectable capsule used in horizontal filter bars.
struct FilterChip: View {
    let title: Text
    var leading: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.kolaTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let leading { Text(leading) }
                title
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                Capsule().fill(isSelected ? theme.accent : theme.card)
            }
            .overlay { Capsule().strokeBorder(theme.separator.opacity(isSelected ? 0 : 0.6)) }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Metric tile

struct MetricTile: View {
    let title: Text
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            title
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Confidence bar

struct ConfidenceBar: View {
    let label: String
    let confidence: Double
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text(confidence, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(tint.opacity(0.15))
                    Capsule().fill(tint).frame(width: max(6, proxy.size.width * confidence))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Plant thumbnail

/// Asynchronously decoded thumbnail with a crop-emoji placeholder.
struct PlantThumbnail: View {
    let data: Data?
    let crop: Crop
    var cornerRadius: CGFloat = 16

    @State private var image: UIImage?
    @Environment(\.kolaTheme) private var theme

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                theme.heroGradient.opacity(0.35)
                Text(crop.emoji)
                    .font(.system(size: 38))
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: data) {
            guard let data else { image = nil; return }
            let decoded = await Task.detached(priority: .utility) { ImageProcessing.thumbnail(from: data) }.value
            withAnimation(.easeOut(duration: 0.2)) { image = decoded }
        }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: Text
    var systemImage: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            if let systemImage {
                Image(systemName: systemImage).foregroundStyle(.tint)
            }
            title.font(.title3.weight(.semibold))
            Spacer()
            if let trailing { trailing }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Viewfinder

/// Four rounded corner brackets used to frame the camera / photo area.
struct ViewfinderCorners: Shape {
    var length: CGFloat = 34
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let l = min(length, rect.width / 3, rect.height / 3)
        let r = cornerRadius
        // top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        // top-right
        path.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        // bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        // bottom-left
        path.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return path
    }
}

// MARK: - Contagiousness meter

struct ContagiousnessMeter: View {
    let level: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index < level ? Color.red.opacity(0.4 + Double(index) * 0.25) : Color.secondary.opacity(0.2))
                    .frame(width: 18, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Spread risk"))
        .accessibilityValue(Text("\(level) of 3"))
    }
}
