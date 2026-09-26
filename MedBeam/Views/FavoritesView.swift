import SwiftUI

/// Favorites tab: your watched medications (Shortage Watch) and recent searches.
struct FavoritesView: View {
    @Environment(AppState.self) private var app
    @State private var medicationSearch: MedicationSearchRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ShortageWatchSection(
                    onSelectSaved: open,
                    onSelectPopular: { drug in medicationSearch = MedicationSearchRequest(text: drug.searchQuery) },
                    onAdd: { medicationSearch = MedicationSearchRequest(text: "") }
                )

                if !app.history.entries.isEmpty {
                    recentSearches
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .refreshable { await app.loadHomeData(force: true) }
        .task { await app.loadHomeData() }
        .appBackground()
        .navigationTitle("Favorites")
        .sheet(item: $medicationSearch) { request in
            // Picking a medication here opens its pharmacy results right away
            MedicationSearchSheet(initialQuery: request.text) { medication in open(medication) }
        }
    }

    /// Shows pharmacies for a medication. Without a ZIP code, goes to Search to enter one.
    private func open(_ medication: Medication) {
        app.selectedMedication = medication
        if app.isZipValid {
            app.showResults()
        } else {
            app.selectedTab = .home
        }
    }

    private var recentSearches: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(title: "Recent searches", icon: "clock.arrow.circlepath")
                Spacer()
                Button("See all") { app.selectedTab = .history }.font(.subheadline)
            }
            VStack(spacing: 0) {
                ForEach(Array(app.history.entries.prefix(5).enumerated()), id: \.element.id) { index, entry in
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
}
