import SwiftUI
import MapKit

struct PharmacyDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    let pharmacy: Pharmacy
    let onCall: () -> Void
    let onReport: () -> Void

    var body: some View {
        let estimate = app.estimate(for: pharmacy)
        let place = app.placeDetails[pharmacy.id]

        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pharmacy.name).font(.title2.bold())
                        Text(pharmacy.address).foregroundStyle(.secondary)
                        Text(String(format: "%.1f miles from %@", pharmacy.distanceMiles, app.zip))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 10) {
                        if let phone = pharmacy.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
                            ActionButton(title: "Call", systemImage: "phone.fill") {
                                onCall()
                                openURL(url)
                            }
                        }
                        ActionButton(title: "Directions", systemImage: "car.fill") {
                            pharmacy.mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                        }
                        if let url = place?.googleMapsURL {
                            ActionButton(title: "Google Maps", systemImage: "star.bubble.fill") { openURL(url) }
                        } else {
                            // Apple Maps' place page shows the pharmacy's hours, ratings and reviews
                            ActionButton(title: "Hours & reviews", systemImage: "clock.fill") { pharmacy.mapItem.openInMaps() }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }

                ratingAndHours(place)

                Section("Estimated availability") {
                    HStack(alignment: .firstTextBaseline) {
                        Text(estimate.headline)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(estimate.tier.color)
                        if estimate.showsPercentage {
                            Text(estimate.tier.rawValue).font(.headline).foregroundStyle(estimate.tier.color)
                        }
                        Spacer()
                        ConfidenceBadge(confidence: estimate.confidence)
                    }
                    if let last = estimate.lastReport {
                        LabeledContent("Last report", value: last.formatted(.relative(presentation: .named)))
                    }
                    if let updated = app.shortage?.lastUpdated {
                        LabeledContent("FDA data updated", value: updated.formatted(date: .abbreviated, time: .omitted))
                    }
                    if estimate.usesSimulatedData {
                        SimulatedBadge()
                    }
                }

                Section {
                    ForEach(estimate.factors) { factor in
                        FactorLine(factor: factor)
                    }
                    if app.isRefiningEstimates {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading more public data…").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Why this estimate?")
                } footer: {
                    Text("From public data alone: \(Int((estimate.publicDataProbability * 100).rounded()))%. Local reports then adjust it.")
                }

                Section("Local reports") {
                    ForEach(estimate.reasons, id: \.self) { reason in
                        Label(reason, systemImage: "person.3")
                            .font(.subheadline)
                    }
                }

                Section {
                    Button(action: onReport) {
                        Label("I checked — report what I found", systemImage: "checkmark.bubble")
                    }
                } footer: {
                    Text(Disclaimer.estimate)
                }
            }
            .appBackground()
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func ratingAndHours(_ place: PlaceDetails?) -> some View {
        if let place {
            Section {
                if let rating = place.rating {
                    HStack(spacing: 6) {
                        Text(String(format: "%.1f", rating)).font(.title3.bold())
                        StarRating(rating: rating)
                        if let count = place.ratingCount {
                            Text("(\(count.formatted()))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rated \(String(format: "%.1f", rating)) out of 5 from \(place.ratingCount ?? 0) reviews")
                }
                if let status = place.openStatusText {
                    Label(status, systemImage: "clock.fill")
                        .foregroundStyle(place.isOpenNow == true ? .green : .red)
                        .font(.subheadline.weight(.semibold))
                }
                if !place.weeklyHours.isEmpty {
                    DisclosureGroup("Weekly hours") {
                        ForEach(place.weeklyHours, id: \.self) { line in
                            Text(line).font(.subheadline)
                        }
                    }
                }
            } header: {
                Text("Rating & hours")
            } footer: {
                Text("Ratings and hours from Google. Pharmacy counter hours may differ from store hours.")
            }
        } else if FeatureFlags.googleRatingsAndHours && !settings.hasGoogleKey {
            Section {
                Label("Add a Google API key in Settings to see ratings and hours here.", systemImage: "star.bubble")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// One public-data factor: an arrow for its direction, plus the detail.
private struct FactorLine: View {
    let factor: EstimateFactor

    private var icon: (name: String, color: Color) {
        switch factor.effect {
        case 0.05...: return ("arrow.up.circle.fill", .green)
        case ..<(-0.05): return ("arrow.down.circle.fill", factor.effect < -0.3 ? .red : .orange)
        default: return ("equal.circle.fill", .gray)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon.name).foregroundStyle(icon.color).font(.body)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(factor.name).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(factor.source).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(factor.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(factor.name): \(factor.direction). \(factor.detail)")
    }
}

private struct StarRating: View {
    let rating: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                let fill = rating - Double(i)
                Image(systemName: fill >= 0.75 ? "star.fill" : fill >= 0.25 ? "star.leadinghalf.filled" : "star")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
            }
        }
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }
}

struct ReportPromptView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pharmacy: Pharmacy
    @State private var thanked = false

    var body: some View {
        VStack(spacing: 16) {
            if thanked {
                Spacer()
                Image(systemName: "heart.circle.fill").font(.system(size: 56)).foregroundStyle(.pink)
                Text("Thanks for helping!").font(.title2.bold())
                Text("Your anonymous answer helps others find their medication.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Spacer()
            } else if !app.canReport(pharmacy) {
                Spacer()
                Image(systemName: "clock.badge.checkmark").font(.system(size: 48)).foregroundStyle(Color.accentColor)
                Text("You already reported this pharmacy").font(.title3.bold()).multilineTextAlignment(.center)
                Text("To keep estimates fair, you can report the same pharmacy and medication once per hour. Thanks for helping!")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("OK") { dismiss() }.buttonStyle(.bordered).controlSize(.large)
                Spacer()
            } else {
                Text("Did \(pharmacy.name) have \(app.selectedMedication?.shortName ?? "your medication")?")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                Button { answer(.inStock) } label: {
                    Label("Yes, they had it", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)

                Button { answer(.outOfStock) } label: {
                    Label("No, they didn't", systemImage: "xmark.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)

                Button("Prefer not to answer") { dismiss() }
                    .controlSize(.large)

                Text(app.reports.isCommunityEnabled
                     ? "Anonymous. Shared with other MedBeam users: only the medication, pharmacy, answer and time."
                     : "Anonymous. We only save the medication, pharmacy, answer and time.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom)
    }

    private func answer(_ result: AvailabilityReport.Result) {
        app.submitReport(result, for: pharmacy)
        withAnimation { thanked = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        }
    }
}
