import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var app
    @State private var confirmClear = false

    private enum Filter: String, CaseIterable { case searches = "Searches", reports = "My reports" }
    @State private var filter: Filter = .searches

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch filter {
            case .searches: searches
            case .reports: myReports
            }
        }
        .appBackground()
        .navigationTitle("History")
        .toolbar {
            if hasItems {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { confirmClear = true }
                }
            }
        }
        .confirmationDialog(filter == .searches ? "Clear search history?" : "Delete all your reports?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button(filter == .searches ? "Clear history" : "Delete reports", role: .destructive) {
                if filter == .searches {
                    app.history.clear()
                } else {
                    app.reports.delete(Set(app.reports.myReports.map(\.id)))
                }
            }
        }
    }

    private var hasItems: Bool {
        filter == .searches ? !app.history.entries.isEmpty : !app.reports.myReports.isEmpty
    }

    @ViewBuilder
    private var searches: some View {
        if app.history.entries.isEmpty {
            emptyState("No searches yet", icon: "magnifyingglass", text: "Medications you search for will show up here.")
        } else {
            Section {
                ForEach(app.history.entries) { entry in
                    Button {
                        app.showResults(zip: entry.zip, medication: entry.medication)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "pills.fill")
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 34, height: 34)
                                .background(Color.accentColor.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.medication.shortName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text("ZIP \(entry.zip) · \(entry.pharmacyCount) pharmacies · \(entry.fdaStatus)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    app.history.delete(Set(offsets.map { app.history.entries[$0].id }))
                }
            } footer: {
                Text("Tap a search to run it again. Saved only on this iPhone.")
            }
        }
    }

    @ViewBuilder
    private var myReports: some View {
        let reports = app.reports.myReports
        if reports.isEmpty {
            emptyState("No reports yet", icon: "checkmark.bubble", text: "After you check a pharmacy, tell RxRadar whether they had it. Your answers appear here.")
        } else {
            Section {
                ForEach(reports) { report in
                    HStack(spacing: 12) {
                        Image(systemName: report.result == .inStock ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(report.result == .inStock ? .green : .red)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(report.pharmacyName ?? "Pharmacy").font(.subheadline.weight(.semibold))
                            Text(report.medicationName ?? "Medication").font(.caption).foregroundStyle(.secondary)
                            Text("\(report.result == .inStock ? "Had it" : "Didn't have it") · \(report.timestamp.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .onDelete { offsets in
                    app.reports.delete(Set(offsets.map { reports[$0].id }))
                }
            } footer: {
                Text(app.reports.isCommunityEnabled
                     ? "Swipe left to remove a report from this iPhone. Shared copies are anonymous and stay in the community database."
                     : "Swipe left to delete a report. Reports are anonymous.")
            }
        }
    }

    private func emptyState(_ title: String, icon: String, text: String) -> some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(text))
            .listRowBackground(Color.clear)
    }
}
