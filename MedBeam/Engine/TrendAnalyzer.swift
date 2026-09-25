import Foundation
import CoreLocation

struct WeeklyPoint: Identifiable {
    /// 0 = this week, 1 = last week, ...
    let weeksAgo: Int
    let rate: Double
    let reportCount: Int

    var id: Int { weeksAgo }
    var label: String { weeksAgo == 0 ? "This wk" : "\(weeksAgo) wk ago" }
}

struct LocalTrend {
    enum Direction: String {
        case improving = "Improving"
        case stable = "Stable"
        case declining = "Declining"
        case notEnoughData = "Not enough reports yet"

        var symbol: String {
            switch self {
            case .improving: return "arrow.up.right"
            case .stable: return "arrow.right"
            case .declining: return "arrow.down.right"
            case .notEnoughData: return "questionmark"
            }
        }
    }

    let points: [WeeklyPoint]
    let direction: Direction
    /// Our model's warning. This is NEVER an official FDA shortage.
    let earlyWarning: String?
    /// How many pharmacies individually show a drop
    let decliningPharmacies: Int
    let usesSimulatedData: Bool
}

/// Detects local trends from community reports. Everything here is labeled as
/// "detected by MedBeam", separate from the official FDA shortage status.
enum TrendAnalyzer {
    static let weeks = 5
    static let minReportsPerWeek = 3
    static let changeThreshold = 0.10

    /// `pharmacies`: the search results; reports at (or within ~75 m of) any of them count as local.
    static func analyze(reports: [AvailabilityReport], pharmacies: [Pharmacy], now: Date = .now) -> LocalTrend {
        let ids = Set(pharmacies.map(\.id))
        let spots = pharmacies.map { CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        let local = reports.filter { report in
            ids.contains(report.pharmacyID)
                || spots.contains { $0.distance(from: report.location) <= AvailabilityEstimator.samePharmacyMeters }
        }

        var points: [WeeklyPoint] = []
        for week in (0..<weeks).reversed() {
            let inWeek = local.filter {
                let age = now.timeIntervalSince($0.timestamp) / 86_400
                return age >= Double(week * 7) && age < Double((week + 1) * 7)
            }
            guard inWeek.count >= minReportsPerWeek else { continue }
            let yes = inWeek.filter { $0.result == .inStock }.count
            points.append(WeeklyPoint(weeksAgo: week, rate: Double(yes) / Double(inWeek.count), reportCount: inWeek.count))
        }

        let direction = direction(of: points)
        let declining = decliningPharmacyCount(local, now: now)
        let latest = points.last?.rate ?? 1

        var warning: String?
        if declining >= 3 {
            warning = "\(declining) pharmacies in this area are reporting declining availability of this medication."
        } else if direction == .declining && latest < 0.5 {
            warning = "Local availability has dropped significantly over the past few weeks."
        }

        return LocalTrend(
            points: points,
            direction: direction,
            earlyWarning: warning,
            decliningPharmacies: declining,
            usesSimulatedData: local.contains { $0.isSimulated }
        )
    }

    /// Compares the average of the two most recent weeks with the two weeks before.
    private static func direction(of points: [WeeklyPoint]) -> LocalTrend.Direction {
        guard points.count >= 3 else { return .notEnoughData }
        let recent = points.suffix(2).map(\.rate)
        let earlier = points.dropLast(2).suffix(2).map(\.rate)
        let change = recent.reduce(0, +) / Double(recent.count) - earlier.reduce(0, +) / Double(earlier.count)
        if change <= -changeThreshold { return .declining }
        if change >= changeThreshold { return .improving }
        return .stable
    }

    /// A pharmacy is "declining" if its last-7-day rate is 25+ points below its 8–30-day rate.
    private static func decliningPharmacyCount(_ reports: [AvailabilityReport], now: Date) -> Int {
        Dictionary(grouping: reports, by: \.pharmacyID).values.filter { group in
            let recent = group.filter { now.timeIntervalSince($0.timestamp) < 7 * 86_400 }
            let older = group.filter {
                let age = now.timeIntervalSince($0.timestamp)
                return age >= 7 * 86_400 && age < 30 * 86_400
            }
            guard recent.count >= 1, older.count >= 2 else { return false }
            return rate(recent) <= rate(older) - 0.25
        }.count
    }

    private static func rate(_ reports: [AvailabilityReport]) -> Double {
        Double(reports.filter { $0.result == .inStock }.count) / Double(reports.count)
    }
}
