import Foundation
import MapKit

/// Finds pharmacies with Apple's built-in MapKit search (free, no API key).
/// MapKit gives name, address, phone and website. It does NOT give ratings or hours to
/// third-party apps; the pharmacy card links to Apple Maps, which shows them.
///
/// Apple limits how many searches an app can make per minute, so each lookup uses
/// only two requests.
struct PharmacySearchService {
    enum SearchError: LocalizedError {
        case zipNotFound
        case noPharmacies(radiusMiles: Int)
        case busy
        case offline

        var errorDescription: String? {
            switch self {
            case .zipNotFound: return "We couldn't find that ZIP code. Check the number and try again."
            case .noPharmacies(let miles): return "No pharmacies found within \(miles) miles of that ZIP code."
            case .busy: return "Apple Maps is busy right now. Wait a few seconds and try again."
            case .offline: return "You appear to be offline. Check your internet connection."
            }
        }
    }

    /// Radii tried in order: nearby first, then wider for rural areas.
    static let searchRadii: [Double] = [8, 25]

    func coordinate(forZIP zip: String) async throws -> CLLocationCoordinate2D {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(zip), United States"
        request.resultTypes = .address
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch {
            throw Self.translate(error, fallback: .zipNotFound)
        }
        // Only accept a result that is actually this ZIP code (fake ZIPs can match random places)
        guard let item = response.mapItems.first(where: { $0.placemark.postalCode == zip }) else {
            throw SearchError.zipNotFound
        }
        return item.placemark.coordinate
    }

    /// Searches nearby first; if nothing is found (rural areas), searches a wider circle.
    func pharmacies(near center: CLLocationCoordinate2D) async throws -> (pharmacies: [Pharmacy], radiusMiles: Double) {
        for radius in Self.searchRadii {
            let found = try await pharmacies(near: center, radiusMiles: radius)
            if !found.isEmpty { return (found, radius) }
        }
        throw SearchError.noPharmacies(radiusMiles: Int(Self.searchRadii.last!))
    }

    func pharmacies(near center: CLLocationCoordinate2D, radiusMiles: Double) async throws -> [Pharmacy] {
        let meters = radiusMiles * 1609.34

        // Request 1: every pharmacy point of interest in the area
        let poiRequest = MKLocalPointsOfInterestRequest(center: center, radius: min(meters, 40_000))
        poiRequest.pointOfInterestFilter = MKPointOfInterestFilter(including: [.pharmacy])

        // Request 2: a text search, which finds stores the first one misses.
        // `.required` keeps results inside the ZIP's area — without it, Apple Maps returns
        // pharmacies near the *phone's* location instead.
        let textRequest = MKLocalSearch.Request()
        textRequest.naturalLanguageQuery = "pharmacy"
        textRequest.resultTypes = .pointOfInterest
        textRequest.region = MKCoordinateRegion(center: center, latitudinalMeters: meters * 2, longitudinalMeters: meters * 2)
        textRequest.regionPriority = .required

        async let poi = Self.run(MKLocalSearch(request: poiRequest))
        async let text = Self.run(MKLocalSearch(request: textRequest))
        let (poiResult, textResult) = await (poi, text)

        // If both requests failed, report why (throttled / offline) instead of "no pharmacies"
        if case .failure(let error) = poiResult, case .failure = textResult {
            throw Self.translate(error, fallback: .busy)
        }
        let textItems = ((try? textResult.get()) ?? []).filter(Self.looksLikePharmacy)
        let items = ((try? poiResult.get()) ?? []) + textItems

        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var byKey: [String: Pharmacy] = [:]
        for item in items {
            let placemark = item.placemark
            let coordinate = placemark.coordinate
            let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) / 1609.34
            guard distance <= radiusMiles else { continue }

            let name = item.name ?? "Pharmacy"
            let address = Self.format(placemark)
            let id = String(format: "%@|%.4f,%.4f", name, coordinate.latitude, coordinate.longitude)
            // Apple Maps sometimes lists the same store twice with slightly different pins
            let key = "\(name.lowercased())|\(address.lowercased())"
            guard byKey[key] == nil else { continue }
            byKey[key] = Pharmacy(
                id: id,
                name: name,
                address: address,
                phone: item.phoneNumber,
                url: item.url,
                coordinate: coordinate,
                distanceMiles: distance,
                mapItem: item
            )
        }

        return Array(byKey.values.sorted { $0.distanceMiles < $1.distanceMiles }.prefix(40))
    }

    /// The text search isn't limited to pharmacies, so keep only real pharmacy listings.
    private static func looksLikePharmacy(_ item: MKMapItem) -> Bool {
        if item.pointOfInterestCategory == .pharmacy { return true }
        let name = (item.name ?? "").lowercased()
        let keywords = ["pharmacy", "drug", "apothecary", "cvs", "walgreens", "rite aid", "duane reade", " rx"]
        return keywords.contains { name.contains($0) }
    }

    private static func run(_ search: MKLocalSearch) async -> Result<[MKMapItem], Error> {
        do {
            return .success(try await search.start().mapItems)
        } catch {
            // "No results" is not a real failure
            if (error as? MKError)?.code == .placemarkNotFound { return .success([]) }
            return .failure(error)
        }
    }

    private static func translate(_ error: Error, fallback: SearchError) -> SearchError {
        if (error as? MKError)?.code == .loadingThrottled { return .busy }
        if (error as? MKError)?.code == .placemarkNotFound { return .zipNotFound }
        if (error as NSError).domain == NSURLErrorDomain { return .offline }
        if let mk = error as? MKError, mk.code == .serverFailure { return .offline }
        return fallback
    }

    private static func format(_ p: MKPlacemark) -> String {
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let cityLine = [p.locality, [p.administrativeArea, p.postalCode].compactMap { $0 }.joined(separator: " ")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return [street, cityLine].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
