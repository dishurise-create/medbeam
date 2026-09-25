import Foundation
import CoreLocation

/// Ratings and opening hours for one pharmacy, from Google.
struct PlaceDetails {
    let name: String
    let rating: Double?
    let ratingCount: Int?
    let isOpenNow: Bool?
    let nextCloseTime: Date?
    let nextOpenTime: Date?
    /// e.g. ["Monday: 8:00 AM – 9:00 PM", ...]
    let weeklyHours: [String]
    let googleMapsURL: URL?
    let coordinate: CLLocationCoordinate2D

    var openStatusText: String? {
        guard let isOpenNow else { return nil }
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        if isOpenNow {
            if let close = nextCloseTime { return "Open until \(close.formatted(time))" }
            return "Open now"
        }
        if let open = nextOpenTime {
            let day = Calendar.current.isDateInToday(open) ? "" : (Calendar.current.isDateInTomorrow(open) ? " tomorrow" : " \(open.formatted(.dateTime.weekday(.abbreviated)))")
            return "Closed · Opens\(day) \(open.formatted(time))"
        }
        return "Closed"
    }

    /// Today's line from the weekly hours, e.g. "8:00 AM – 9:00 PM"
    var todayHours: String? {
        let weekday = Date.now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))
        return weeklyHours.first { $0.hasPrefix(weekday) }?
            .replacingOccurrences(of: "\(weekday): ", with: "")
    }
}

/// Google Places API (New) — Nearby Search.
/// One request returns up to 20 pharmacies with ratings + hours, which are then
/// matched to the Apple Maps results. Requires an API key with billing enabled
/// (Google gives a free monthly allowance; rating/hours fields use the "Enterprise" tier).
/// Docs: https://developers.google.com/maps/documentation/places/web-service/nearby-search
struct GooglePlacesService {
    enum PlacesError: LocalizedError {
        case badKey(String)
        var errorDescription: String? {
            switch self { case .badKey(let message): return message }
        }
    }

    let apiKey: String

    func pharmacies(near center: CLLocationCoordinate2D, radiusMeters: Double) async throws -> [PlaceDetails] {
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchNearby")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        // Lets you restrict the key to this app in Google Cloud Console
        request.setValue(Bundle.main.bundleIdentifier, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.setValue(
            "places.displayName,places.location,places.rating,places.userRatingCount,places.currentOpeningHours,places.googleMapsUri",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        let body: [String: Any] = [
            "includedTypes": ["pharmacy", "drugstore"],
            "maxResultCount": 20,
            "rankPreference": "DISTANCE",
            "locationRestriction": [
                "circle": [
                    "center": ["latitude": center.latitude, "longitude": center.longitude],
                    "radius": min(radiusMeters, 50_000),
                ],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (try? JSONDecoder().decode(GoogleError.self, from: data))?.error.message
            throw PlacesError.badKey(message ?? "Google returned error \(http.statusCode).")
        }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> [PlaceDetails] {
        let decoder = JSONDecoder()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { d in
            let text = try d.singleValueContainer().decode(String.self)
            if let date = iso.date(from: text) ?? isoPlain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "Bad date \(text)"))
        }
        let response = try decoder.decode(NearbyResponse.self, from: data)
        return (response.places ?? []).map { place in
            PlaceDetails(
                name: place.displayName?.text ?? "",
                rating: place.rating,
                ratingCount: place.userRatingCount,
                isOpenNow: place.currentOpeningHours?.openNow,
                nextCloseTime: place.currentOpeningHours?.nextCloseTime,
                nextOpenTime: place.currentOpeningHours?.nextOpenTime,
                weeklyHours: place.currentOpeningHours?.weekdayDescriptions ?? [],
                googleMapsURL: place.googleMapsUri.flatMap(URL.init(string:)),
                coordinate: CLLocationCoordinate2D(latitude: place.location.latitude, longitude: place.location.longitude)
            )
        }
    }

    /// Finds the Google place for an Apple Maps pharmacy: close by (< 150 m) and a similar name.
    static func match(_ pharmacy: Pharmacy, in places: [PlaceDetails]) -> PlaceDetails? {
        let here = CLLocation(latitude: pharmacy.coordinate.latitude, longitude: pharmacy.coordinate.longitude)
        let firstWord = pharmacy.name.lowercased().split(separator: " ").first.map(String.init) ?? ""
        var best: (place: PlaceDetails, distance: Double)?
        for place in places {
            let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            let distance = here.distance(from: location)
            let similarName = place.name.lowercased().contains(firstWord)
            guard distance < 150, distance < 40 || similarName else { continue }
            if best == nil || distance < best!.distance { best = (place, distance) }
        }
        return best?.place
    }
}

private struct NearbyResponse: Decodable {
    struct Place: Decodable {
        struct Text: Decodable { let text: String }
        struct Location: Decodable { let latitude: Double; let longitude: Double }
        struct Hours: Decodable {
            let openNow: Bool?
            let weekdayDescriptions: [String]?
            let nextCloseTime: Date?
            let nextOpenTime: Date?
        }
        let displayName: Text?
        let location: Location
        let rating: Double?
        let userRatingCount: Int?
        let currentOpeningHours: Hours?
        let googleMapsUri: String?
    }
    let places: [Place]?
}

private struct GoogleError: Decodable {
    struct Body: Decodable { let message: String }
    let error: Body
}
