import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var confirmDelete = false
    @State private var keyDraft = ""
    @State private var showKey = false
    @State private var versionTaps = 0
    @AppStorage("showPresentationTools") private var showPresentationTools = false

    var body: some View {
        @Bindable var settings = settings
        @Bindable var app = app

        Form {
            // MARK: Appearance
            Section("Appearance") {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(AppSettings.Theme.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Background")
                    SwatchRow(options: AppSettings.Background.allCases, selection: $settings.background) { option in
                        option == .standard ? Color(.systemGray5) : option.tint
                    }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Accent color")
                    SwatchRow(options: AppSettings.Accent.allCases, selection: $settings.accent) { $0.color }
                }
                .padding(.vertical, 4)

                Picker("Text size", selection: $settings.textSize) {
                    ForEach(AppSettings.TextSize.allCases) { Text($0.rawValue).tag($0) }
                }
                .tint(settings.accent.color)
                Text("Preview: Adderall XR 20 mg, 89% at CVS Pharmacy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // MARK: Ratings & hours (turned off in the App Store version — see FeatureFlags)
            if FeatureFlags.googleRatingsAndHours {
            Section {
                HStack {
                    Group {
                        if showKey {
                            TextField("Paste API key", text: $keyDraft)
                        } else {
                            SecureField("Paste API key", text: $keyDraft)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(showKey ? "Hide key" : "Show key")
                }
                HStack {
                    Button("Save key") {
                        settings.googleAPIKey = keyDraft
                        Task { await app.findPharmacies(force: true) }
                    }
                    .disabled(keyDraft == settings.googleAPIKey)
                    Spacer()
                    if settings.hasGoogleKey {
                        Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.subheadline)
                    }
                }
                if settings.hasGoogleKey {
                    Button("Remove key", role: .destructive) {
                        settings.googleAPIKey = ""
                        keyDraft = ""
                    }
                }
                if let error = app.googleError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("Ratings & hours (Google)")
            } footer: {
                Text("Apple Maps doesn't share ratings or hours with apps, so MedBeam can get them from Google Places. Create a key in Google Cloud Console with \"Places API (New)\" enabled. Google includes a free monthly allowance; billing must be turned on. The key is stored in your iPhone's Keychain.")
            }
            }

            // MARK: Data
            Section {
                LabeledContent("Community sharing") {
                    Text(app.reports.isCommunityEnabled ? "On" : "Not set up")
                        .foregroundStyle(app.reports.isCommunityEnabled ? .green : .secondary)
                }
                LabeledContent("Your reports", value: "\(app.reports.realReportCount)")
                LabeledContent("Saved searches", value: "\(app.history.entries.count)")
                Button("Delete all data on this iPhone", role: .destructive) { confirmDelete = true }
            } header: {
                Text("Data")
            }

            // MARK: Presentation tools (hidden: tap Version 5 times)
            if showPresentationTools || app.demoMode {
                Section {
                    Toggle("Demo mode", isOn: $app.demoMode)
                    Button("Hide presentation tools") {
                        app.demoMode = false
                        showPresentationTools = false
                    }
                } header: {
                    Text("Presentation tools")
                } footer: {
                    Text("For demonstrations only. Demo mode adds clearly labeled simulated reports. Simulated reports are never shared with other users.")
                }
            }

            // MARK: Important info
            Section("Important information") {
                NavigationLink { InfoPage.estimates } label: { Label("How estimates work", systemImage: "function") }
                NavigationLink { InfoPage.cantFind } label: { Label("Can't find your medication?", systemImage: "questionmark.bubble") }
                NavigationLink { InfoPage.privacy } label: { Label("Privacy", systemImage: "hand.raised.fill") }
                NavigationLink { InfoPage.medical } label: { Label("Medical safety", systemImage: "cross.case") }
                NavigationLink { InfoPage.sources } label: { Label("Data sources", systemImage: "building.columns") }
                Link(destination: URL(string: "tel:911")!) {
                    Label("Medical emergency? Call 911", systemImage: "phone.fill").foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTaps += 1
                        if versionTaps >= 5 {
                            versionTaps = 0
                            withAnimation { showPresentationTools = true }
                        }
                    }
                Text("Built for the 2026 Congressional App Challenge.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .appBackground()
        .navigationTitle("Settings")
        .onAppear { keyDraft = settings.googleAPIKey }
        .confirmationDialog("Delete all data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete reports and history", role: .destructive) {
                app.reports.clearAll()
                app.history.clear()
            }
        } message: {
            Text("This removes your reports, simulated data and search history from this iPhone.")
        }
    }
}

private struct SwatchRow<Option: Identifiable & Hashable & RawRepresentable>: View where Option.RawValue == String {
    let options: [Option]
    @Binding var selection: Option
    let color: (Option) -> Color

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options) { option in
                Button { selection = option } label: {
                    Circle()
                        .fill(color(option).gradient)
                        .frame(width: 34, height: 34)
                        .overlay {
                            if option == selection {
                                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                            }
                        }
                        .overlay(Circle().stroke(Color.primary.opacity(option == selection ? 0.6 : 0.1), lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.rawValue)
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Simple text pages for the "Important information" section.
struct InfoPage: View {
    let title: String
    let sections: [(heading: String, body: String)]

    var body: some View {
        List {
            ForEach(sections, id: \.heading) { section in
                Section(section.heading) {
                    Text(section.body)
                }
            }
        }
        .appBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    static let estimates = InfoPage(title: "How estimates work", sections: [
        ("No live inventory", "No public system shares pharmacies' live prescription stock. MedBeam never claims to know exactly what's on the shelf."),
        ("Step 1: A percentage from public data", "MedBeam starts with the official FDA Drug Shortages status for your exact medication, strength and form. It then adjusts for how commonly the medication is prescribed (Medicaid data), whether it is a controlled substance, how many companies make it, recent recalls, the wholesale price trend, its form, and the type of pharmacy. This works even with zero users. Each pharmacy's card lists every factor."),
        ("Step 2: Local reports", "People who check a pharmacy can anonymously report whether it had the medication. Recent reports count the most; a report's weight halves every 4 days, and reports older than 30 days are ignored."),
        ("Step 3: Nearby pharmacies", "Reports from other pharmacies within 5 miles count a little, because shortages are often regional."),
        ("How to read the percentage", "The percentage is an informed estimate, not a measurement. The label next to it shows how much local evidence is behind it. \"Public data only\" means nobody has reported for that pharmacy yet, so similar pharmacies nearby show similar numbers. It changes to \"Some local reports\" and then \"Many local reports\" as people share what they found. Always call to confirm."),
        ("Supply risk score", "A 0 to 100 national score combining four public sources: FDA shortage status, how many separately approved products exist (FDA NDC Directory), recalls in the last 6 months (FDA Enforcement Reports), and the 3-month trend in what pharmacies pay (Medicaid NADAC). An official FDA shortage always rates at least Elevated. It describes the medication nationally, not any single pharmacy."),
        ("Official vs. detected", "\"Official FDA shortage\" only appears when the FDA lists one. Local declines detected from reports are labeled separately and are never called official shortages."),
    ])

    static let cantFind = InfoPage(title: "Can't find it?", sections: [
        ("Ask the pharmacist", "Pharmacists can often check stock at other locations of the same chain and transfer your prescription."),
        ("Call before you drive", "Estimates can be wrong. Use the Call button to confirm before making a trip."),
        ("Talk to your doctor", "If your medication is in shortage, your doctor may be able to suggest options. Never change your medication or dose on your own."),
        ("Check the FDA", "The FDA Drug Shortages list shows official shortages and expected recovery dates."),
    ])

    static let privacy = InfoPage(title: "Privacy", sections: [
        ("What we never ask for", "Your name, prescription number, doctor, diagnosis, insurance or medical history."),
        ("What a report contains", "Only the medication, pharmacy, whether they had it, and the time. \"Prefer not to answer\" saves nothing."),
        ("What is shared", "When community sharing is on, each report sends only the medication ID, the pharmacy's map location, whether it had the medication, and the time. No name, account, device ID or your location."),
        ("Where data is stored", "Your search history, saved medications, your own reports and settings stay on this iPhone."),
        ("Location", "MedBeam uses the ZIP code you type. It does not track your GPS location."),
    ])

    static let medical = InfoPage(title: "Medical safety", sections: [
        ("Information only", "MedBeam is an information tool, not medical advice. It does not diagnose or treat any condition."),
        ("Your medication", "Never change your medication, dose or schedule without talking to your doctor or pharmacist."),
        ("Emergencies", "If you or someone else is having a medical emergency, call 911."),
    ])

    static let sources = InfoPage(title: "Data sources", sections: [
        ("FDA Drug Shortages", "Official U.S. Food and Drug Administration shortage data through openFDA (open.fda.gov). Updated by the FDA as manufacturers report."),
        ("RxNorm", "The National Library of Medicine's standard drug names, used to match your exact medication, strength and form."),
        ("Apple Maps", "Pharmacy names, addresses, phone numbers and locations."),
        ("FDA NDC Directory & Enforcement Reports", "How many approved products exist for a medication, whether it is a controlled substance, and any recalls in the last 6 months (open.fda.gov)."),
        ("Medicaid drug utilization", "How many prescriptions were filled nationally last year, a measure of how commonly pharmacies stock a medication (data.medicaid.gov)."),
        ("Medicaid NADAC", "The government's weekly survey of what pharmacies pay for medications (data.medicaid.gov). Rising prices can signal tight supply."),
        ("Community reports", "Anonymous \"had it / didn't\" answers from people using MedBeam."),
    ])
}
