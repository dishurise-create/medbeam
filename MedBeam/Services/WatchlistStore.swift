import Foundation
import Observation

/// Latest status for one saved medication, shown on the home screen.
struct WatchStatus {
    let fda: ShortageStatus
    /// Community reports near the user's ZIP in the last 30 days (nil = sharing not set up / offline)
    let nearbyReports: Int?
    let nearbyHadIt: Int?
}

/// "My medications": medications the user saved to check quickly. Stored on this iPhone only.
@MainActor
@Observable
final class WatchlistStore {
    private(set) var medications: [Medication] = []
    private(set) var statuses: [String: WatchStatus] = [:]
    private let key = "watchlist"

    init() {
        if let data = UserDefaults.standard.data(forKey: key) {
            medications = (try? JSONDecoder().decode([Medication].self, from: data)) ?? []
        }
    }

    func contains(_ medication: Medication) -> Bool {
        medications.contains { $0.rxcui == medication.rxcui }
    }

    func toggle(_ medication: Medication) {
        if contains(medication) {
            remove([medication.rxcui])
        } else {
            medications.insert(medication, at: 0)
            save()
        }
    }

    func remove(_ rxcuis: Set<String>) {
        medications.removeAll { rxcuis.contains($0.rxcui) }
        rxcuis.forEach { statuses[$0] = nil }
        save()
    }

    func setStatus(_ status: WatchStatus, for rxcui: String) {
        statuses[rxcui] = status
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(medications), forKey: key)
    }
}
