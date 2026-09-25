import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class AppState {
    enum Tab: Hashable { case home, history, settings }
    enum Route: Hashable { case results }

    var selectedTab: Tab = .home
    var homePath: [Route] = []

    /// Remembered between launches so users don't have to retype it.
    var zip = UserDefaults.standard.string(forKey: "lastZIP") ?? "" {
        didSet { if isZipValid { UserDefaults.standard.set(zip, forKey: "lastZIP") } }
    }
    var selectedMedication: Medication? = AppState.loadLastMedication() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(selectedMedication), forKey: "lastMedication") }
    }

    private static func loadLastMedication() -> Medication? {
        guard let data = UserDefaults.standard.data(forKey: "lastMedication") else { return nil }
        return try? JSONDecoder().decode(Medication.self, from: data)
    }

    private(set) var center: CLLocationCoordinate2D?
    /// Set when the user taps "Search this area" on the map instead of using the ZIP center.
    private var areaOverride: CLLocationCoordinate2D?
    private(set) var pharmacies: [Pharmacy] = []
    private(set) var shortage: ShortageStatus?
    private(set) var isLoading = false
    /// True when results are for a map area the user picked, not the ZIP center.
    private(set) var isSearchingArea = false
    var errorMessage: String?

    /// Google ratings + hours, keyed by pharmacy ID. Empty if no API key is set.
    private(set) var placeDetails: [String: PlaceDetails] = [:]
    private(set) var googleError: String?

    /// ZIP + medication of the last finished search, so returning to the map doesn't search again.
    private var lastSearchKey: String?

    /// Demo mode fills the app with clearly labeled simulated reports for presentations.
    var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: "demoMode")
            if !demoMode { reports.clearSimulated() } else { seedDemoData() }
        }
    }

    let settings: AppSettings
    let reports = ReportStore()
    let history = HistoryStore()
    private let rxNorm = RxNormService()
    private let fda = FDAShortageService()
    private let places = PharmacySearchService()
    /// Radius actually used for the last search (wider in rural areas)
    private(set) var searchRadiusMiles = 8.0

    init(settings: AppSettings) {
        self.settings = settings
        demoMode = UserDefaults.standard.object(forKey: "demoMode") as? Bool ?? true
    }

    var isZipValid: Bool { zip.count == 5 && zip.allSatisfy(\.isNumber) }
    var canSearch: Bool { isZipValid && selectedMedication != nil }

    func searchMedications(_ query: String) async throws -> [Medication] {
        try await rxNorm.search(query)
    }

    /// Opens the results map for a ZIP + medication (used by Home and History).
    func showResults(zip: String? = nil, medication: Medication? = nil) {
        if let zip { self.zip = zip }
        if let medication { selectedMedication = medication }
        selectedTab = .home
        homePath = [.results]
    }

    /// Re-searches around a spot the user moved the map to.
    func searchArea(around coordinate: CLLocationCoordinate2D) async {
        areaOverride = coordinate
        await findPharmacies(force: true)
    }

    func findPharmacies(force: Bool = false) async {
        guard let medication = selectedMedication, isZipValid else { return }
        let key = "\(zip)|\(medication.rxcui)|\(settings.hasGoogleKey)"
        if !force { areaOverride = nil }
        guard force || key != lastSearchKey || pharmacies.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        googleError = nil
        // Clear the previous search so nothing stale shows if this one fails
        pharmacies = []
        placeDetails = [:]
        shortage = nil
        if areaOverride == nil { center = nil }
        defer { isLoading = false }

        do {
            let center: CLLocationCoordinate2D
            if let areaOverride {
                center = areaOverride
            } else {
                center = try await places.coordinate(forZIP: zip)
            }
            self.center = center
            isSearchingArea = areaOverride != nil

            let details = (try? await rxNorm.details(for: medication)) ?? .basic(medication)
            async let foundPharmacies = places.pharmacies(near: center)
            async let shortageStatus = fda.status(for: details)

            let status = await shortageStatus
            shortage = status
            let found = try await foundPharmacies
            pharmacies = found.pharmacies
            searchRadiusMiles = found.radiusMiles
            lastSearchKey = key
            seedDemoData()
            if areaOverride == nil { history.record(zip: zip, medication: medication, fdaStatus: status.headline, pharmacyCount: pharmacies.count) }
            await loadGoogleDetails(center: center)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadGoogleDetails(center: CLLocationCoordinate2D) async {
        guard settings.hasGoogleKey else { return }
        do {
            let service = GooglePlacesService(apiKey: settings.googleAPIKey)
            let found = try await service.pharmacies(near: center, radiusMeters: searchRadiusMiles * 1609.34)
            var matched: [String: PlaceDetails] = [:]
            for pharmacy in pharmacies {
                if let place = GooglePlacesService.match(pharmacy, in: found) { matched[pharmacy.id] = place }
            }
            placeDetails = matched
        } catch {
            googleError = error.localizedDescription
        }
    }

    // MARK: - Estimates

    var currentReports: [AvailabilityReport] {
        guard let medication = selectedMedication else { return [] }
        return reports.reports(for: medication.rxcui, includeSimulated: demoMode)
    }

    func estimate(for pharmacy: Pharmacy) -> AvailabilityEstimate {
        AvailabilityEstimator.estimate(
            for: pharmacy,
            shortage: shortage ?? .unknown(),
            reports: currentReports
        )
    }

    /// Pharmacies sorted by best chance of having the medication, then by distance.
    var rankedPharmacies: [(pharmacy: Pharmacy, estimate: AvailabilityEstimate)] {
        pharmacies
            .map { ($0, estimate(for: $0)) }
            .sorted { a, b in
                if abs(a.1.probability - b.1.probability) > 0.02 { return a.1.probability > b.1.probability }
                return a.0.distanceMiles < b.0.distanceMiles
            }
    }

    var localTrend: LocalTrend {
        TrendAnalyzer.analyze(reports: currentReports, pharmacies: pharmacies)
    }

    // MARK: - Reports

    /// `nil` means "Prefer not to answer" — nothing is saved.
    func submitReport(_ result: AvailabilityReport.Result?, for pharmacy: Pharmacy) {
        guard let result, let medication = selectedMedication else { return }
        reports.add(result, medication: medication, pharmacy: pharmacy)
    }

    private func seedDemoData() {
        guard demoMode, let medication = selectedMedication, let shortage, !pharmacies.isEmpty else { return }
        reports.seedSimulatedIfNeeded(medication: medication, pharmacies: pharmacies, nationalScore: shortage.nationalSupplyScore)
    }
}
