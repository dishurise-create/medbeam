import Foundation
import Observation

struct SearchHistoryEntry: Codable, Identifiable {
    let id: UUID
    let zip: String
    let medication: Medication
    let date: Date
    let fdaStatus: String
    let pharmacyCount: Int
}

/// Past searches, saved on this device only.
@MainActor
@Observable
final class HistoryStore {
    private(set) var entries: [SearchHistoryEntry] = []
    private let key = "searchHistory"

    init() {
        if let data = UserDefaults.standard.data(forKey: key) {
            entries = (try? JSONDecoder().decode([SearchHistoryEntry].self, from: data)) ?? []
        }
    }

    func record(zip: String, medication: Medication, fdaStatus: String, pharmacyCount: Int) {
        // Keep one entry per ZIP + medication, most recent first
        entries.removeAll { $0.zip == zip && $0.medication.rxcui == medication.rxcui }
        entries.insert(SearchHistoryEntry(id: UUID(), zip: zip, medication: medication, date: .now, fdaStatus: fdaStatus, pharmacyCount: pharmacyCount), at: 0)
        entries = Array(entries.prefix(50))
        save()
    }

    func delete(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}
