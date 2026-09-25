import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    /// Set to open the medication search sheet (optionally pre-filled)
    @State private var medicationSearch: MedicationSearchRequest?
    @AppStorage("hideHowItWorks") private var hideHowItWorks = false
    @FocusState private var zipFocused: Bool

    var body: some View {
        @Bindable var app = app

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BrandHeader()

                VStack(spacing: 0) {
                    // ZIP code
                    HStack(spacing: 14) {
                        FieldIcon(systemImage: "mappin.and.ellipse")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ZIP code").font(.caption).foregroundStyle(.secondary)
                            TextField("Enter ZIP", text: $app.zip)
                                .font(.title3.weight(.semibold))
                                .keyboardType(.numberPad)
                                .textContentType(.postalCode)
                                .focused($zipFocused)
                                .onChange(of: app.zip) { _, new in
                                    let cleaned = String(new.filter(\.isNumber).prefix(5))
                                    if cleaned != new { app.zip = cleaned }
                                }
                        }
                        if !app.zip.isEmpty {
                            Button {
                                app.zip = ""
                                zipFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear ZIP code")
                        }
                    }
                    .padding(16)

                    Divider().padding(.leading, 70)

                    // Medication
                    Button {
                        zipFocused = false
                        openMedicationSearch()
                    } label: {
                        HStack(spacing: 14) {
                            FieldIcon(systemImage: "pills.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Medication").font(.caption).foregroundStyle(.secondary)
                                Text(app.selectedMedication?.shortName ?? "Search by name")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(app.selectedMedication == nil ? .tertiary : .primary)
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.selectedMedication.map { "Medication: \($0.displayName). Tap to change." } ?? "Choose a medication")
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                Button {
                    zipFocused = false
                    app.showResults()
                } label: {
                    Text("Find pharmacies")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(!app.canSearch)

                if !hideHowItWorks {
                    HowItWorksCard { withAnimation { hideHowItWorks = true } }
                }

                MyMedicationsSection(onSelect: open)

                ShortageWatchSection { drug in openMedicationSearch(drug.searchQuery) }

                if !app.history.entries.isEmpty {
                    recentSearches
                }

                Label("Anonymous. No account or prescription info needed.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        // Blurred strip behind the clock/battery so scrolled content stays readable
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: 0).background(.bar, ignoresSafeAreaEdges: .top)
        }
        .refreshable { await app.loadHomeData(force: true) }
        .task { await app.loadHomeData() }
        .appBackground()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { zipFocused = false }
            }
        }
        .sheet(item: $medicationSearch) { request in
            MedicationSearchSheet(initialQuery: request.text)
        }
        #if DEBUG
        .task { await runAutomationIfRequested() }
        #endif
    }

    private func openMedicationSearch(_ text: String = "") {
        medicationSearch = MedicationSearchRequest(text: text)
    }

    /// Opens results for a saved medication (asks for a ZIP first if there isn't one).
    private func open(_ medication: Medication) {
        app.selectedMedication = medication
        if app.isZipValid {
            app.showResults()
        } else {
            zipFocused = true
        }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent").font(.headline)
                Spacer()
                Button("See all") { app.selectedTab = .history }.font(.subheadline)
            }
            VStack(spacing: 0) {
                ForEach(Array(app.history.entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider().padding(.leading, 16) }
                    Button {
                        app.showResults(zip: entry.zip, medication: entry.medication)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.medication.shortName).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text("ZIP \(entry.zip) · \(entry.date.formatted(.relative(presentation: .named)))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.forward").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    #if DEBUG
    /// Testing shortcut: launch with `-autoZip 20105 -autoQuery "adderall 20"` to skip typing.
    private func runAutomationIfRequested() async {
        let defaults = UserDefaults.standard
        guard let zip = defaults.string(forKey: "autoZip"),
              let autoQuery = defaults.string(forKey: "autoQuery"),
              let med = try? await app.searchMedications(autoQuery).first else { return }
        app.zip = zip
        app.selectedMedication = med
        if defaults.bool(forKey: "autoOpenResults") { app.showResults() }
    }
    #endif
}

struct MedicationSearchRequest: Identifiable {
    let id = UUID()
    let text: String
}

private struct FieldIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 40, height: 40)
            .background(Color.accentColor.opacity(0.12), in: Circle())
    }
}

struct MedicationSearchSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query: String

    /// `initialQuery` pre-fills the search (e.g. when tapping a Shortage Watch tile).
    init(initialQuery: String = "") {
        _query = State(initialValue: initialQuery)
    }
    @State private var results: [Medication] = []
    @State private var isSearching = false
    @State private var message: String?

    private let suggestions = ["Adderall", "Methylphenidate", "Amoxicillin", "Albuterol", "Ozempic", "Lisdexamfetamine"]

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).count < 3 {
                    Section("Commonly searched") {
                        ForEach(suggestions, id: \.self) { name in
                            Button { query = name } label: {
                                Label(name, systemImage: "magnifyingglass")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } else if let message {
                    Text(message).foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(results) { med in
                            Button {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                app.selectedMedication = med
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(med.shortName).foregroundStyle(.primary)
                                    Text(med.isBrand ? "Brand name" : "Generic")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        if !results.isEmpty { Text("Pick the exact strength and form on your prescription label.") }
                    }
                }
            }
            .appBackground()
            .overlay { if isSearching && results.isEmpty { ProgressView() } }
            .navigationTitle("Medication")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "e.g. Adderall XR 20")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task(id: query) { await search() }

        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3 else { results = []; message = nil; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await app.searchMedications(text)
            guard !Task.isCancelled else { return }
            results = Array(found.prefix(30))
            message = found.isEmpty ? "No matches. Try the brand or generic name." : nil
        } catch {
            guard !Task.isCancelled else { return }
            message = "Couldn't reach the medication database. Check your connection."
        }
    }
}
