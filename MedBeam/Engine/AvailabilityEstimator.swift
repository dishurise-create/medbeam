import Foundation
import CoreLocation

struct AvailabilityEstimate {
    enum Tier: String {
        case likely = "Likely"
        case uncertain = "Uncertain"
        case unlikely = "Unlikely"
    }

    enum Confidence: String {
        case low = "Low confidence"
        case moderate = "Moderate confidence"
        case high = "High confidence"
    }

    /// 0...1 chance the pharmacy has the medication
    let probability: Double
    let tier: Tier
    let confidence: Confidence
    /// Percentages are only shown once there are real local reports for this pharmacy.
    /// Before that, showing "78%" would be fake precision, so we show the tier instead.
    let showsPercentage: Bool
    let lastReport: Date?
    let reasons: [String]
    let usesSimulatedData: Bool

    var percentText: String { "\(Int((probability * 100).rounded()))%" }
    var headline: String { showsPercentage ? percentText : tier.rawValue }
}

/// How the estimate works (a Bayesian "prior + evidence" model):
///
/// 1. START with the national supply signal from the FDA shortage database.
///    This works with zero users. It counts as `priorWeight` pretend reports.
/// 2. ADD reports for this exact pharmacy. Newer reports count more:
///    a report's weight halves every `halfLifeDays` days.
/// 3. ADD reports from other pharmacies within `areaRadiusMiles`, at a lower
///    weight (`areaWeight`), because shortages are often regional.
///
/// estimate = (prior + weighted "had it" reports) / (prior weight + all weighted reports)
enum AvailabilityEstimator {
    static let priorWeight = 3.0
    static let halfLifeDays = 4.0
    static let maxAgeDays = 30.0
    static let areaRadiusMiles = 5.0
    static let areaWeight = 0.25
    /// Apple Maps can return slightly different coordinates for the same store on different
    /// searches, so a report within this distance counts as "this pharmacy".
    static let samePharmacyMeters = 75.0
    /// Reports for the same spot within this window count as ONE report,
    /// so a burst of spam (or one person tapping repeatedly) can't swing the estimate.
    static let burstWindow: TimeInterval = 30 * 60

    /// A group of reports for the same spot within `burstWindow`, treated as one report.
    struct Burst {
        let pharmacyIDs: Set<String>
        let location: CLLocation
        let timestamp: Date
        /// Share of reports in the burst that said "had it" (0...1)
        let yesFraction: Double
        let isSimulated: Bool
    }

    static func bursts(_ reports: [AvailabilityReport]) -> [Burst] {
        // Key: ~50 m grid cell + 30-minute time slot
        let groups = Dictionary(grouping: reports) { r in
            "\(Int((r.latitude * 2000).rounded()))|\(Int((r.longitude * 2000).rounded()))|\(Int(r.timestamp.timeIntervalSince1970 / burstWindow))"
        }
        return groups.values.map { group in
            Burst(
                pharmacyIDs: Set(group.map(\.pharmacyID)),
                location: group[0].location,
                timestamp: group.map(\.timestamp).max()!,
                yesFraction: Double(group.filter { $0.result == .inStock }.count) / Double(group.count),
                isSimulated: group.contains { $0.isSimulated }
            )
        }
    }

    static func estimate(
        for pharmacy: Pharmacy,
        shortage: ShortageStatus,
        reports: [AvailabilityReport],
        now: Date = .now
    ) -> AvailabilityEstimate {
        let prior = shortage.nationalSupplyScore
        var hadIt = prior * priorWeight
        var didnt = (1 - prior) * priorWeight

        var direct: (weight: Double, yes: Int, no: Int) = (0, 0, 0)
        var area: (weight: Double, yes: Int, no: Int) = (0, 0, 0)
        var lastReport: Date?
        var usesSimulated = false
        let here = CLLocation(latitude: pharmacy.coordinate.latitude, longitude: pharmacy.coordinate.longitude)

        for burst in bursts(reports) {
            let ageDays = now.timeIntervalSince(burst.timestamp) / 86_400
            guard ageDays >= 0, ageDays <= maxAgeDays else { continue }
            let recency = pow(0.5, ageDays / halfLifeDays)
            let isYes = burst.yesFraction >= 0.5

            let distance = burst.location.distance(from: here)
            if burst.pharmacyIDs.contains(pharmacy.id) || distance <= samePharmacyMeters {
                direct.weight += recency
                if isYes { direct.yes += 1 } else { direct.no += 1 }
                hadIt += recency * burst.yesFraction
                didnt += recency * (1 - burst.yesFraction)
                lastReport = max(lastReport ?? burst.timestamp, burst.timestamp)
                usesSimulated = usesSimulated || burst.isSimulated
            } else if distance / 1609.34 <= areaRadiusMiles {
                let weight = recency * areaWeight
                area.weight += weight
                if isYes { area.yes += 1 } else { area.no += 1 }
                hadIt += weight * burst.yesFraction
                didnt += weight * (1 - burst.yesFraction)
                usesSimulated = usesSimulated || burst.isSimulated
            }
        }

        let probability = hadIt / (hadIt + didnt)
        let tier: AvailabilityEstimate.Tier = probability >= 0.65 ? .likely : probability >= 0.35 ? .uncertain : .unlikely
        let confidence: AvailabilityEstimate.Confidence
        if direct.weight >= 2.5 {
            confidence = .high
        } else if direct.weight >= 0.8 || area.weight >= 1.0 {
            confidence = .moderate
        } else {
            confidence = .low
        }

        var reasons = [nationalReason(shortage)]
        if direct.yes + direct.no > 0 {
            reasons.append("\(direct.yes + direct.no) report\(direct.yes + direct.no == 1 ? "" : "s") for this pharmacy in the last 30 days: \(direct.yes) had it, \(direct.no) didn't. Recent reports count more.")
        } else {
            reasons.append("No reports for this pharmacy yet.")
        }
        if area.yes + area.no > 0 {
            reasons.append("\(area.yes + area.no) report\(area.yes + area.no == 1 ? "" : "s") from other pharmacies within \(Int(areaRadiusMiles)) miles (\(area.yes) had it) — these count less.")
        }
        if direct.yes + direct.no == 0 && area.yes + area.no == 0 {
            reasons.append("With no local reports, this is based only on national supply, so nearby pharmacies show the same level.")
        }

        return AvailabilityEstimate(
            probability: probability,
            tier: tier,
            confidence: confidence,
            showsPercentage: direct.weight >= 0.9,
            lastReport: lastReport,
            reasons: reasons,
            usesSimulatedData: usesSimulated
        )
    }

    private static func nationalReason(_ shortage: ShortageStatus) -> String {
        switch shortage.level {
        case .none:
            return "FDA does not list this medication as being in shortage."
        case .active:
            let known = shortage.manufacturers.filter { $0.category != .unknown }
            let good = known.filter { $0.category == .available }.count
            return "FDA lists an official shortage. \(good) of \(known.count) manufacturers report the product as available."
        case .resolved:
            return "FDA lists a past shortage for this medication as resolved."
        case .discontinuing:
            return "FDA lists this product as being discontinued by at least one manufacturer."
        case .unknown:
            return "Couldn't reach the FDA shortage database, so a neutral starting estimate is used."
        }
    }
}
