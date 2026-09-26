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

// MARK: - Shortage Watch (personalized)

/// Shows the user's saved medications ("Mine"), or popular medications ("Popular").
/// With nothing saved yet, it shows Popular plus a tip on how to save.
struct ShortageWatchSection: View {
    @Environment(AppState.self) private var app
    let onSelectSaved: (Medication) -> Void
    let onSelectPopular: (WatchedDrug) -> Void
    let onAdd: () -> Void

    private enum Mode: String, CaseIterable { case mine = "My medications", popular = "Popular" }
    @State private var mode: Mode = .mine

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var hasSaved: Bool { !app.watchlist.medications.isEmpty }
    private var showingMine: Bool { hasSaved && mode == .mine }

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

            if hasSaved {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill").font(.title3).foregroundStyle(.yellow)
                    Text("Make this yours: tap the ☆ on any search to watch your own medications here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14)
            }

            if showingMine {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(app.watchlist.medications, id: \.rxcui) { medication in
                        Button { onSelectSaved(medication) } label: {
                            SavedMedicationTile(medication: medication, status: app.watchlist.statuses[medication.rxcui], zip: app.zip)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Stop watching", systemImage: "star.slash", role: .destructive) {
                                app.watchlist.remove([medication.rxcui])
                            }
                        }
                    }
                    Button(action: onAdd) { AddTile() }
                        .buttonStyle(.plain)
                }
                Text("Your saved medications: FDA status, national supply risk and reports near you. Touch and hold to stop watching.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if app.shortageWatchFailed {
                Label("Couldn't reach the FDA. Pull down to try again.", systemImage: "wifi.exclamationmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(WatchedDrug.featured) { drug in
                        Button { onSelectPopular(drug) } label: {
                            ShortageTile(drug: drug, summary: app.shortageWatch[drug.id])
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Commonly hard-to-find medications. Official FDA listings for any strength or form. Tap to search.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Tile for one saved medication.
private struct SavedMedicationTile: View {
    let medication: Medication
    let status: WatchStatus?
    let zip: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(medication.shortName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            if let status {
                let inShortage = status.fda.level == .active
                HStack(spacing: 5) {
                    Circle().fill(inShortage ? Color.red : Color.green).frame(width: 8, height: 8)
                    Text(inShortage ? "FDA shortage" : "No shortage")
                        .font(.caption.bold())
                        .foregroundStyle(inShortage ? .red : .green)
                }
                if let risk = status.supplyRisk {
                    Text("Supply risk: \(risk.level.rawValue)")
                        .font(.caption2.bold())
                        .foregroundStyle(risk.level == .low ? .green : risk.level == .high ? .red : .orange)
                }
                Text(reportText(status))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func reportText(_ status: WatchStatus) -> String {
        guard let total = status.nearbyReports else { return zip.isEmpty ? "Add a ZIP for local reports" : "Tap to see pharmacies" }
        if total == 0 { return "No reports near \(zip) yet" }
        return "\(total) report\(total == 1 ? "" : "s") nearby · \(status.nearbyHadIt ?? 0) had it"
    }
}

private struct AddTile: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text("Add medication")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Add a medication to watch")
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
