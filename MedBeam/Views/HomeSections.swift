import SwiftUI

// MARK: - Brand header

/// Navy "night sky" card with a golden beam, matching the app icon.
struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image("Logo")
                    .resizable()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
                    .accessibilityHidden(true)
                Text("MedBeam")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 8)

            Text("Find your medication.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("See which pharmacies near you are most likely to have it, and spot shortages early.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background {
            ZStack {
                LinearGradient(colors: [Color(red: 0.055, green: 0.10, blue: 0.20), Color(red: 0.12, green: 0.29, blue: 0.54)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // Golden beam from the top-right corner, like the icon
                RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.45).opacity(0.55), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 260)
                // A few sparkles
                GeometryReader { geo in
                    ForEach(Array([(0.86, 0.18, 14.0), (0.93, 0.42, 9.0), (0.74, 0.10, 8.0)].enumerated()), id: \.offset) { _, s in
                        Image(systemName: "sparkle")
                            .font(.system(size: s.2))
                            .foregroundStyle(.white.opacity(0.85))
                            .position(x: geo.size.width * s.0, y: geo.size.height * s.1)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - How it works

struct HowItWorksCard: View {
    let onDismiss: () -> Void

    private let steps: [(icon: String, title: String)] = [
        ("magnifyingglass", "Search your medication"),
        ("map.fill", "See likely pharmacies"),
        ("checkmark.bubble.fill", "Report what you found"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("How it works").font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide how it works")
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    VStack(spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: step.icon)
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 52, height: 52)
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.accentColor, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                        Text(step.title)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(index + 1): \(step.title)")
                }
            }
            Text("Your reports are anonymous and help your neighbors find their medication too.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

// MARK: - My medications

struct MyMedicationsSection: View {
    @Environment(AppState.self) private var app
    let onSelect: (Medication) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "My medications", icon: "star.fill")

            if app.watchlist.medications.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "star")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                    Text("Tap the ☆ on any search to save a medication here and check it quickly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.watchlist.medications.enumerated()), id: \.element.rxcui) { index, medication in
                        if index > 0 { Divider().padding(.leading, 16) }
                        Button { onSelect(medication) } label: {
                            WatchRow(medication: medication, status: app.watchlist.statuses[medication.rxcui], zip: app.zip)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Remove from My medications", systemImage: "star.slash", role: .destructive) {
                                app.watchlist.remove([medication.rxcui])
                            }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("Touch and hold a medication to remove it.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct WatchRow: View {
    let medication: Medication
    let status: WatchStatus?
    let zip: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.shortName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let status {
                    Label(status.fda.level.headline, systemImage: status.fda.level == .active ? "exclamationmark.octagon.fill" : "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(status.fda.level == .active ? .red : .green)
                    Text(communityText(status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Checking…").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func communityText(_ status: WatchStatus) -> String {
        guard let total = status.nearbyReports else { return "Tap to see pharmacies near \(zip.isEmpty ? "you" : zip)" }
        if total == 0 { return "No reports near \(zip) in the last 30 days" }
        return "\(total) report\(total == 1 ? "" : "s") near \(zip) · \(status.nearbyHadIt ?? 0) had it"
    }
}

// MARK: - Shortage Watch

struct ShortageWatchSection: View {
    @Environment(AppState.self) private var app
    let onSelect: (WatchedDrug) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title: "Shortage Watch", icon: "waveform.path.ecg")
                Spacer()
                Text("Live FDA data")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }

            if app.shortageWatchFailed {
                Label("Couldn't reach the FDA. Pull down to try again.", systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(WatchedDrug.featured) { drug in
                        Button { onSelect(drug) } label: {
                            ShortageTile(drug: drug, summary: app.shortageWatch[drug.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Official FDA shortage listings for any strength or form. Tap a medication to search for it.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct ShortageTile: View {
    let drug: WatchedDrug
    let summary: DrugShortageSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(drug.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(drug.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let summary {
                HStack(spacing: 5) {
                    Circle()
                        .fill(summary.inShortage ? Color.red : Color.green)
                        .frame(width: 8, height: 8)
                    Text(summary.inShortage ? "Shortage" : "No shortage")
                        .font(.caption.bold())
                        .foregroundStyle(summary.inShortage ? .red : .green)
                }
                if summary.inShortage {
                    Text("\(summary.limited + summary.unavailable) of \(summary.listedProducts) products limited")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Shared

struct SectionTitle: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline)
            .labelStyle(.titleAndIcon)
    }
}
