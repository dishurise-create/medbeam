import SwiftUI

enum Disclaimer {
    static let estimate = "This is an estimate based on national supply, FDA shortage data, and local availability reports. It does not guarantee the medication is in stock — call the pharmacy to confirm."
    static let medical = "MedBeam is an information tool, not medical advice. Never change your medication or dose without talking to your doctor or pharmacist."
}

extension AvailabilityEstimate.Tier {
    var color: Color {
        switch self {
        case .likely: return .green
        case .uncertain: return .orange
        case .unlikely: return .red
        }
    }

    var shortLabel: String {
        switch self {
        case .likely: return "Likely"
        case .uncertain: return "Maybe"
        case .unlikely: return "Unlikely"
        }
    }
}

struct ConfidenceBadge: View {
    let confidence: AvailabilityEstimate.Confidence

    var body: some View {
        let bars = confidence == .high ? 3 : confidence == .moderate ? 2 : 1
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < bars ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 3, height: CGFloat(5 + i * 3))
                }
            }
            Text(confidence.rawValue)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(confidence.rawValue)
    }
}

struct ShortageChip: View {
    let level: ShortageStatus.Level

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var title: String { level.headline }

    private var icon: String {
        switch level {
        case .none, .resolved: return "checkmark.seal.fill"
        case .active: return "exclamationmark.octagon.fill"
        case .discontinuing: return "minus.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch level {
        case .none, .resolved: return .green
        case .active: return .red
        case .discontinuing: return .orange
        case .unknown: return .gray
        }
    }
}

struct SimulatedBadge: View {
    var body: some View {
        Label("Includes simulated demo reports", systemImage: "testtube.2")
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.15), in: Capsule())
            .foregroundStyle(.purple)
    }
}
