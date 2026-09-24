import Foundation
import Observation

/// Stores anonymous availability reports.
///
/// MVP: saved on this device as a JSON file. Later this can be swapped for a shared
/// database (e.g. CloudKit or Firebase) so every user's reports help everyone else.
/// Only medication, pharmacy, result and time are stored — never who reported it.
@MainActor
@Observable
final class ReportStore {
    private(set) var all: [AvailabilityReport] = []
    private let fileURL: URL

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = folder.appendingPathComponent("reports.json")
        load()
    }

    func reports(for rxcui: String, includeSimulated: Bool) -> [AvailabilityReport] {
        all.filter { $0.rxcui == rxcui && (includeSimulated || !$0.isSimulated) }
    }

    func add(_ result: AvailabilityReport.Result, medication: Medication, pharmacy: Pharmacy) {
        all.append(AvailabilityReport(
            id: UUID(),
            rxcui: medication.rxcui,
            pharmacyID: pharmacy.id,
            latitude: pharmacy.coordinate.latitude,
            longitude: pharmacy.coordinate.longitude,
            result: result,
            timestamp: .now,
            isSimulated: false,
            medicationName: medication.shortName,
            pharmacyName: pharmacy.name
        ))
        save()
    }

    /// Your own reports, newest first (for the History tab).
    var myReports: [AvailabilityReport] {
        all.filter { !$0.isSimulated }.sorted { $0.timestamp > $1.timestamp }
    }

    func delete(_ ids: Set<UUID>) {
        all.removeAll { ids.contains($0.id) }
        save()
    }

    var realReportCount: Int { all.filter { !$0.isSimulated }.count }

    func clearSimulated() {
        all.removeAll { $0.isSimulated }
        save()
    }

    func clearAll() {
        all.removeAll()
        save()
    }

    /// Adds demo reports for pharmacies that don't have any yet for this medication.
    func seedSimulatedIfNeeded(medication: Medication, pharmacies: [Pharmacy], nationalScore: Double) {
        let seeded = Set(all.filter { $0.isSimulated && $0.rxcui == medication.rxcui }.map(\.pharmacyID))
        let new = pharmacies
            .filter { !seeded.contains($0.id) }
            .flatMap { DemoDataGenerator.reports(medication: medication, pharmacy: $0, nationalScore: nationalScore) }
        guard !new.isEmpty else { return }
        all += new
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        all = (try? JSONDecoder().decode([AvailabilityReport].self, from: data)) ?? []
    }

    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: fileURL, options: .atomic)
    }
}

/// Generates believable, clearly labeled demo reports so the map and trends can be
/// demonstrated before real users exist. Same pharmacy + medication always gives the same data.
enum DemoDataGenerator {
    static func reports(medication: Medication, pharmacy: Pharmacy, nationalScore: Double) -> [AvailabilityReport] {
        var rng = SeededGenerator(seed: stableHash(pharmacy.id + medication.rxcui))

        // ~20% of pharmacies get no reports, so the demo also shows "low confidence".
        if Double.random(in: 0..<1, using: &rng) < 0.2 { return [] }

        let base = min(0.95, max(0.1, nationalScore + Double.random(in: -0.45...0.4, using: &rng)))
        let isDeclining = Double.random(in: 0..<1, using: &rng) < 0.45
        let count = Int.random(in: 2...10, using: &rng)
        let days = 35.0

        return (0..<count).map { _ in
            let ageDays = Double.random(in: 0..<days, using: &rng)
            // Declining pharmacies had better stock earlier and worse stock recently.
            let drift = isDeclining ? 0.4 * (ageDays / days) - 0.2 : 0
            let chance = min(0.97, max(0.03, base + drift))
            let inStock = Double.random(in: 0..<1, using: &rng) < chance
            return AvailabilityReport(
                id: UUID(),
                rxcui: medication.rxcui,
                pharmacyID: pharmacy.id,
                latitude: pharmacy.coordinate.latitude,
                longitude: pharmacy.coordinate.longitude,
                result: inStock ? .inStock : .outOfStock,
                timestamp: Date.now.addingTimeInterval(-ageDays * 86_400),
                isSimulated: true
            )
        }
    }

    /// FNV-1a hash. Swift's built-in hashValue changes every launch, so it can't be used here.
    private static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
