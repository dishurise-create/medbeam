import Foundation
import CoreLocation

/// Shares anonymous availability reports between all RxRadar users through a
/// Supabase (PostgreSQL) database, using its built-in REST API — no extra libraries.
///
/// Each shared report contains ONLY: medication ID (RxCUI), the pharmacy's map
/// location, whether it was in stock, and the time (set by the server).
/// No names, accounts, device IDs or user locations are ever sent.
struct CommunityReportService {
    enum ServiceError: LocalizedError {
        case server(Int, String)
        var errorDescription: String? {
            switch self {
            case .server(let code, let message): return "Community server error \(code): \(message)"
            }
        }
    }

    let baseURL: URL
    let apiKey: String
    var session: URLSession = .shared

    /// nil when BackendConfig hasn't been filled in.
    static func configured() -> CommunityReportService? {
        let url = BackendConfig.supabaseURL.trimmingCharacters(in: .whitespaces)
        let key = BackendConfig.supabasePublishableKey.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, !key.isEmpty, let base = URL(string: url) else { return nil }
        return CommunityReportService(baseURL: base, apiKey: key)
    }

    /// Sends one report. Returns the server's ID and time for it.
    func upload(rxcui: String, coordinate: CLLocationCoordinate2D, inStock: Bool) async throws -> (id: UUID, createdAt: Date) {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/reports"))
        request.httpMethod = "POST"
        addHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "rxcui": rxcui,
            // Rounded to ~1 m: enough to identify the pharmacy, nothing more
            "latitude": (coordinate.latitude * 100_000).rounded() / 100_000,
            "longitude": (coordinate.longitude * 100_000).rounded() / 100_000,
            "in_stock": inStock,
        ])
        let rows: [Row] = try await send(request)
        guard let row = rows.first, let date = Self.parseDate(row.created_at) else {
            throw ServiceError.server(0, "No report returned")
        }
        return (row.id, date)
    }

    /// Reports for one medication near a point, from the last `days` days.
    func fetch(rxcui: String, near center: CLLocationCoordinate2D, radiusMiles: Double, days: Double = 30) async throws -> [AvailabilityReport] {
        // Bounding box around the search area (1° latitude ≈ 69 miles)
        let latDelta = radiusMiles / 69
        let lonDelta = radiusMiles / max(1, 69 * cos(center.latitude * .pi / 180))
        let since = Date.now.addingTimeInterval(-days * 86_400)

        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/reports"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,rxcui,latitude,longitude,in_stock,created_at"),
            URLQueryItem(name: "rxcui", value: "eq.\(rxcui)"),
            URLQueryItem(name: "latitude", value: "gte.\(center.latitude - latDelta)"),
            URLQueryItem(name: "latitude", value: "lte.\(center.latitude + latDelta)"),
            URLQueryItem(name: "longitude", value: "gte.\(center.longitude - lonDelta)"),
            URLQueryItem(name: "longitude", value: "lte.\(center.longitude + lonDelta)"),
            URLQueryItem(name: "created_at", value: "gte.\(Self.isoString(since))"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "2000"),
        ]
        var request = URLRequest(url: components.url!)
        addHeaders(to: &request)
        let rows: [Row] = try await send(request)
        return rows.compactMap { row in
            guard let date = Self.parseDate(row.created_at) else { return nil }
            return AvailabilityReport(
                id: row.id,
                rxcui: row.rxcui,
                pharmacyID: "",               // matched to pharmacies by location
                latitude: row.latitude,
                longitude: row.longitude,
                result: row.in_stock ? .inStock : .outOfStock,
                timestamp: date,
                isSimulated: false,
                fromCommunity: true
            )
        }
    }

    // MARK: - Private

    private struct Row: Decodable {
        let id: UUID
        let rxcui: String
        let latitude: Double
        let longitude: Double
        let in_stock: Bool
        let created_at: String
    }

    private struct ErrorBody: Decodable { let message: String? }

    private func addHeaders(to request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        // Legacy "anon" keys are JWTs and also go in Authorization; new publishable keys don't.
        if apiKey.hasPrefix("eyJ") {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 15
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
            throw ServiceError.server(status, message ?? String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)   // e.g. 2026-09-24T01:02:03Z (no "+" to escape)
    }

    /// PostgreSQL returns times like "2026-09-24T01:02:03.123456+00:00" (6 decimal places),
    /// which Apple's parser can't read, so extra decimals are trimmed first.
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: trimmed) ?? plain.date(from: trimmed)
    }
}
