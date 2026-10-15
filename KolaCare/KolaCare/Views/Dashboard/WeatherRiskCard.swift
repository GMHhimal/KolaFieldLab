//
//  WeatherRiskCard.swift
//  KolaCare
//
//  Current conditions plus the diseases most likely to strike in the next 48 hours.
//

import SwiftUI

struct WeatherRiskCard: View {
    let viewModel: DashboardViewModel
    var onRetry: () -> Void

    @Environment(\.kolaTheme) private var theme
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: Text("Disease risk · next 48 h"), systemImage: "cloud.sun.rain.fill")

            if let forecast = viewModel.forecast {
                conditions(forecast)
                    .transition(.opacity)
                riskList
            } else if viewModel.isLoading || viewModel.state == .idle {
                conditionsPlaceholder
            } else if case .failed(let message) = viewModel.state {
                ContentUnavailableView {
                    Label("Weather unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again", action: onRetry)
                }
            }

            if viewModel.isShowingCachedData {
                Label("Showing saved forecast — you're offline.", systemImage: "icloud.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
        .animation(.easeInOut, value: viewModel.state)
    }

    private func conditions(_ forecast: WeatherForecast) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { conditionTiles(forecast) }
            VStack(spacing: 10) { conditionTiles(forecast) }
        }
    }

    @ViewBuilder
    private func conditionTiles(_ forecast: WeatherForecast) -> some View {
        MetricTile(title: Text(WeatherCondition.description(for: forecast.current.weatherCode)),
                   value: forecast.current.temperature.formatted(.number.precision(.fractionLength(0))) + "°C",
                   systemImage: WeatherCondition.symbol(for: forecast.current.weatherCode),
                   tint: .orange)
        MetricTile(title: Text("Humidity"),
                   value: (forecast.current.humidity / 100).formatted(.percent.precision(.fractionLength(0))),
                   systemImage: "humidity.fill",
                   tint: .blue)
        MetricTile(title: Text("Leaf-wet hours"),
                   value: "\(viewModel.wetHours) h",
                   systemImage: "drop.fill",
                   tint: .teal)
    }

    private var conditionsPlaceholder: some View {
        HStack(spacing: 10) {
            MetricTile(title: Text("Weather"), value: "28°C", systemImage: "cloud.sun.fill")
            MetricTile(title: Text("Humidity"), value: "80%", systemImage: "humidity.fill")
            MetricTile(title: Text("Leaf-wet hours"), value: "12 h", systemImage: "drop.fill")
        }
        .shimmering(true)
    }

    @ViewBuilder
    private var riskList: some View {
        let shown = expanded ? viewModel.risks : Array(viewModel.risks.prefix(3))
        if viewModel.risks.isEmpty {
            Label("No weather-sensitive diseases for your crops.", systemImage: "checkmark.seal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(shown) { risk in
                    NavigationLink(value: risk.disease) {
                        RiskRow(risk: risk)
                    }
                    .buttonStyle(.plain)
                    if risk.id != shown.last?.id { Divider().padding(.leading, 44) }
                }
            }
            if viewModel.risks.count > 3 {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
                } label: {
                    Label(expanded ? LocalizedStringKey("Show less") : LocalizedStringKey("Show all \(viewModel.risks.count)"),
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct RiskRow: View {
    let risk: DiseaseRisk
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(risk.level.color.opacity(0.18))
                    .frame(width: 32, height: 32)
                    .scaleEffect(pulsing ? 1.25 : 1)
                    .opacity(pulsing ? 0.4 : 1)
                Text(risk.disease.crop.emoji).font(.callout)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(risk.disease.name).font(.subheadline.weight(.semibold))
                Text("\(risk.favourableHours) favourable hours in the next \(risk.windowHours) h")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(risk.level.title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(risk.level == .low ? Color.primary : Color.white)
                .background(risk.level.color.opacity(risk.level == .low ? 0.2 : 1), in: Capsule())
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onAppear {
            guard risk.level == .high, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulsing = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the disease guide"))
    }
}
