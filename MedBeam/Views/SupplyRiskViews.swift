import SwiftUI

extension SupplyRisk.Level {
    var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .elevated: return .orange
        case .high: return .red
        }
    }
}

/// Small "Supply risk: Elevated" label used on results and My medications.
struct SupplyRiskChip: View {
    let risk: SupplyRisk

    var body: some View {
        Label("Supply risk: \(risk.level.rawValue)", systemImage: "gauge.with.dots.needle.50percent")
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(risk.level.color.opacity(0.15), in: Capsule())
            .foregroundStyle(risk.level == .moderate ? Color.orange.opacity(0.9) : risk.level.color)
            .accessibilityLabel("National supply risk \(risk.level.rawValue), \(risk.points) out of 100")
    }
}

/// Semicircle gauge 0–100.
struct RiskGauge: View {
    let score: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.5, to: 1)
                .stroke(Color(.tertiarySystemFill), style: StrokeStyle(lineWidth: 14, lineCap: .round))
            Circle()
                .trim(from: 0.5, to: 0.5 + 0.5 * max(0.02, min(score, 1)))
                .stroke(color.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            Text("\(Int((score * 100).rounded()))")
                .font(.system(.title, design: .rounded, weight: .bold))
                .offset(y: -12)
        }
        .frame(width: 120, height: 120)
        .frame(height: 70, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// Full breakdown, shown on the Trends screen.
struct SupplyRiskSection: View {
    let risk: SupplyRisk?
    let isLoading: Bool

    var body: some View {
        Section {
            if let risk {
                HStack(spacing: 16) {
                    RiskGauge(score: risk.score, color: risk.level.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(risk.level.rawValue)
                            .font(.title2.bold())
                            .foregroundStyle(risk.level.color)
                        Text("National supply risk")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("National supply risk: \(risk.level.rawValue), \(risk.points) out of 100")

                ForEach(risk.factors) { factor in
                    FactorRow(factor: factor)
                }
                if risk.officialShortage {
                    Label("An official FDA shortage always rates at least Elevated.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !risk.unavailableSources.isEmpty {
                    Label("No data for this medication from: \(risk.unavailableSources.joined(separator: ", ")). The score uses the other sources.",
                          systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if isLoading {
                HStack {
                    ProgressView()
                    Text("Checking FDA and Medicaid data…").foregroundStyle(.secondary)
                }
            } else {
                Text("Supply risk couldn't be loaded. Check your connection and search again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("Supply risk")
                Spacer()
                Text("Public data · national").font(.caption2.bold()).textCase(nil)
            }
        } footer: {
            Text("How fragile the supply of this medication is across the U.S. It does not show whether a specific pharmacy has it. That comes from local reports.")
        }
    }
}

private struct FactorRow: View {
    let factor: SupplyRisk.Factor

    private var color: Color {
        switch factor.risk {
        case ..<0.25: return .green
        case ..<0.5: return .yellow
        case ..<0.75: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(factor.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(factor.source).font(.caption2).foregroundStyle(.tertiary)
            }
            // Risk bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(color.gradient)
                        .frame(width: max(6, geo.size.width * factor.risk))
                }
            }
            .frame(height: 6)
            Text(factor.detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
