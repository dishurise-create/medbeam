import SwiftUI
import MapKit

struct PharmacyDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    let pharmacy: Pharmacy
    let onCall: () -> Void
    let onReport: () -> Void
    @State private var showWhy = false

    var body: some View {
        let estimate = app.estimate(for: pharmacy)
        let place = app.placeDetails[pharmacy.id]

        ScrollView {
            VStack(spacing: 18) {
                // Who
                HStack(spacing: 12) {
                    PharmacyAvatar(name: pharmacy.name, size: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pharmacy.name).font(.title3.bold()).lineLimit(2)
                        Text("\(pharmacy.address) · \(String(format: "%.1f mi", pharmacy.distanceMiles))")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }

                // The answer
                HStack(spacing: 20) {
                    PercentRing(probability: estimate.probability, color: estimate.tier.color)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(estimate.tier.rawValue + " in stock")
                            .font(.headline)
                            .foregroundStyle(estimate.tier.color)
                        ForEach(highlights(estimate)) { item in
                            HStack(spacing: 6) {
                                Image(systemName: item.up ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, item.up ? Color.green : Color.orange)
                                Text(item.text).foregroundStyle(.primary)
                            }
                            .font(.subheadline)
                        }
                        ConfidenceBadge(confidence: estimate.confidence)
                        if estimate.usesSimulatedData { SimulatedBadge() }
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(estimate.percentText) estimated chance, \(estimate.tier.rawValue). \(estimate.confidence.rawValue).")

                // What to do
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

                Button(action: onReport) {
                    Label("I checked. Report what I found", systemImage: "checkmark.bubble.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrandButtonStyle())

                ratingAndHours(place)

                // The details, tucked away
                DisclosureGroup(isExpanded: $showWhy) {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(estimate.factors) { factor in
                            FactorLine(factor: factor)
                        }
                        if app.isRefiningEstimates {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Loading more public data…").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        ForEach(estimate.reasons, id: \.self) { reason in
                            Label(reason, systemImage: "person.3").font(.caption)
                        }
                        Text("From public data alone: \(Int((estimate.publicDataProbability * 100).rounded()))%. Local reports then adjust it.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let last = estimate.lastReport {
                            Text("Last report \(last.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                        }
                        if let updated = app.shortage?.lastUpdated {
                            Text("FDA data updated \(updated.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 12)
                } label: {
                    Label("See why", systemImage: "list.bullet.rectangle").font(.subheadline.weight(.semibold))
                }
                .card()

                Text(Disclaimer.estimate)
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
            .padding(.top, 8)
        }
        .appBackground()
    }

    private struct Highlight: Identifiable {
        let text: String
        let up: Bool
        var id: String { text }
    }

    /// The FDA status plus the two factors that moved the number the most.
    private func highlights(_ estimate: AvailabilityEstimate) -> [Highlight] {
        var items: [Highlight] = []
        if let base = estimate.factors.first(where: { $0.name == "FDA shortage status" }) {
            let level = app.shortage?.level ?? .unknown
            items.append(Highlight(text: base.short, up: level == .none || level == .resolved))
        }
        let others = estimate.factors
            .filter { $0.name != "FDA shortage status" && abs($0.effect) > 0.05 && !$0.short.isEmpty }
            .sorted { abs($0.effect) > abs($1.effect) }
            .prefix(2)
        items += others.map { Highlight(text: $0.short, up: $0.effect > 0) }
        return items
    }

    @ViewBuilder
    private func ratingAndHours(_ place: PlaceDetails?) -> some View {
        if let place {
            VStack(alignment: .leading, spacing: 8) {
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
                            Text(line).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                Text("Ratings and hours from Google. Pharmacy counter hours may differ from store hours.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        } else if FeatureFlags.googleRatingsAndHours && !settings.hasGoogleKey {
            Label("Add a Google API key in Settings to see ratings and hours here.", systemImage: "star.bubble")
                .font(.footnote).foregroundStyle(.secondary)
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
    @Environment(AppSettings.self) private var settings
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
            .padding(.vertical, 10)
            .background(settings.accent.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(settings.accent.color)
    }
}

struct ReportPromptView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    let pharmacy: Pharmacy
    @State private var thanked = false

    var body: some View {
        VStack(spacing: 16) {
            if thanked {
                Spacer()
                Image(systemName: "heart.circle.fill").font(.system(size: 56)).foregroundStyle(.pink)
                    .symbolEffect(.bounce, value: thanked)
                    .transition(.scale.combined(with: .opacity))
                Text("Thanks for helping!").font(.title2.bold())
                Text("Your anonymous answer helps others find their medication.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Spacer()
            } else if !app.canReport(pharmacy) {
                Spacer()
                Image(systemName: "clock.badge.checkmark").font(.system(size: 48)).foregroundStyle(settings.accent.color)
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
        .sensoryFeedback(.success, trigger: thanked)
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
