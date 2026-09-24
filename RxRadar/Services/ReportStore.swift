import Foundation
import CoreLocation
import Observation

/// Stores anonymous availability reports.
///
/// - Your own reports are saved on this iPhone (for History) and, when the community
///   database is set up (see BackendConfig), shared so they help everyone nearby.
/// - Other people's reports are downloaded for the area you search and kept in memory only.
/// Only medication, pharmacy location, result and time are ever shared — never who reported it.
@MainActor
@Observable
final class ReportStore {
    enum CommunityStatus: Equatable {
        case notConfigured
        case syncing
        case connected(reportCount: Int)
        case failed(String)
    }

    /// Reports saved on this iPhone: your own + simulated demo reports.
    private(set) var all: [AvailabilityReport] = []
    /// Other users' reports for the current search area (not saved).
    private(set) var community: [AvailabilityReport] = []
    private(set) var communityStatus: CommunityStatus
    private let fileURL: URL
    private let service: CommunityReportService?

    /// Unsent reports older than this are kept on the phone but not shared,
    /// because the server would stamp them with the wrong (current) time.
    private let maxUploadDelay: TimeInterval = 2 * 3600

    init(service: CommunityReportService? = CommunityReportService.configured()) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = folder.appendingPathComponent("reports.json")
        self.service = service
        communityStatus = service == nil ? .notConfigured : .connected(reportCount: 0)
        load()
    }

    var isCommunityEnabled: Bool { service != nil }

    /// Everything the estimator should see for one medication.
    func reports(for rxcui: String, includeSimulated: Bool) -> [AvailabilityReport] {
        let mine = all.filter { $0.rxcui == rxcui && (includeSimulated || !$0.isSimulated) }
        // Your shared reports also come back from the server — don't count them twice
        let myRemoteIDs = Set(all.compactMap(\.remoteID))
        let others = community.filter { $0.rxcui == rxcui && !myRemoteIDs.contains($0.id) }
        return mine + others
    }

    func add(_ result: AvailabilityReport.Result, medication: Medication, pharmacy: Pharmacy) {
        let report = AvailabilityReport(
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
        )
        all.append(report)
        save()
        Task { await uploadPending() }
    }

    /// Your own reports, newest first (for the History tab).
    var myReports: [AvailabilityReport] {
        all.filter { !$0.isSimulated }.sorted { $0.timestamp > $1.timestamp }
    }

    var realReportCount: Int { all.filter { !$0.isSimulated }.count }

    // MARK: - Community sync

    /// Shares any of your reports that haven't been sent yet (e.g. you were offline).
    func uploadPending() async {
        guard let service else { return }
        let pending = all.filter {
            !$0.isSimulated && $0.remoteID == nil && Date.now.timeIntervalSince($0.timestamp) < maxUploadDelay
        }
        for report in pending {
            do {
                let saved = try await service.upload(
                    rxcui: report.rxcui,
                    coordinate: CLLocationCoordinate2D(latitude: report.latitude, longitude: report.longitude),
                    inStock: report.result == .inStock
                )
                if let index = all.firstIndex(where: { $0.id == report.id }) {
                    all[index].remoteID = saved.id
                }
            } catch {
                communityStatus = .failed(error.localizedDescription)
                break   // probably offline — try again on the next search
            }
        }
        save()
    }

    /// Downloads other people's reports for a medication around the searched area.
    func syncCommunity(rxcui: String, center: CLLocationCoordinate2D, radiusMiles: Double) async {
        guard let service else { return }
        communityStatus = .syncing
        await uploadPending()
        do {
            // Include a margin so reports from pharmacies just outside the circle still count as "nearby"
            let fetched = try await service.fetch(rxcui: rxcui, near: center, radiusMiles: radiusMiles + AvailabilityEstimator.areaRadiusMiles)
            community = fetched
            let myRemoteIDs = Set(all.compactMap(\.remoteID))
            communityStatus = .connected(reportCount: fetched.filter { !myRemoteIDs.contains($0.id) }.count)
        } catch {
            community = []
            communityStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Local data

    /// Removes reports from this iPhone. (Shared copies stay in the community database,
    /// which only holds anonymous data and can't be edited by the app.)
    func delete(_ ids: Set<UUID>) {
        all.removeAll { ids.contains($0.id) }
        save()
    }

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
