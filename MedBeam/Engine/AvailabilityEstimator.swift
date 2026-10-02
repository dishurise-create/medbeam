import Foundation
import CoreLocation

struct AvailabilityEstimate {
    enum Tier: String {
        case likely = "Likely"
        case uncertain = "Uncertain"
        case unlikely = "Unlikely"
    }

    enum Confidence: String {
        // The label says how much LOCAL evidence is behind the percentage
        case low = "Public data only"
        case moderate = "Some local reports"
        case high = "Many local reports"
    }

    /// 0...1 chance the pharmacy has the medication
    let probability: Double
    let tier: Tier
    let confidence: Confidence
    /// Always true now: the percentage is built from public data even without local reports.
    /// The confidence level tells the user how much local evidence is behind it.
    let showsPercentage: Bool
    /// Public-data factors behind the starting percentage (before crowd reports)
    var factors: [EstimateFactor] = []
    /// The percentage from public data alone, before crowd reports adjusted it
    var publicDataProbability: Double = 0
    let lastReport: Date?
    let reasons: [String]
    let usesSimulatedData: Bool

    var percentText: String { "\(Int((probability * 100).rounded()))%" }
    var headline: String { showsPercentage ? percentText : tier.rawValue }
}

/// How the estimate works (a Bayesian "prior + evidence" model):
///
/// 1. START with a percentage built from public data (see PriorModel): FDA shortage status,
///    how common the drug is, controlled-substance status, makers, recalls, price trend,
///    form and pharmacy type. This works with zero users. It counts as `priorWeight` pretend reports.
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
        signals: DrugSignals? = nil,
        medication: Medication? = nil,
        reports: [AvailabilityReport],
        now: Date = .now
    ) -> AvailabilityEstimate {
        let model = PriorModel.prior(shortage: shortage, signals: signals, medication: medication, pharmacy: pharmacy)
        let prior = model.probability
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

        var reasons: [String] = []
        if direct.yes + direct.no > 0 {
            reasons.append("\(direct.yes + direct.no) report\(direct.yes + direct.no == 1 ? "" : "s") for this pharmacy in the last 30 days: \(direct.yes) had it, \(direct.no) didn't. Recent reports count more.")
        } else {
            reasons.append("No reports for this pharmacy yet.")
        }
        if area.yes + area.no > 0 {
            reasons.append("\(area.yes + area.no) report\(area.yes + area.no == 1 ? "" : "s") from other pharmacies within \(Int(areaRadiusMiles)) miles (\(area.yes) had it) — these count less.")
        }
        if direct.yes + direct.no == 0 && area.yes + area.no == 0 {
            reasons.append("With no local reports yet, this percentage comes from public data only, so similar pharmacies nearby show similar numbers. Call to confirm.")
        }

        return AvailabilityEstimate(
            probability: probability,
            tier: tier,
            confidence: confidence,
            showsPercentage: true,
            factors: model.factors,
            publicDataProbability: prior,
            lastReport: lastReport,
            reasons: reasons,
            usesSimulatedData: usesSimulated
        )
    }
}
