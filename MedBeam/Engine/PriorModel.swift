import Foundation

/// What kind of pharmacy this is, guessed from its name.
enum PharmacyKind: String {
    case chain = "Large chain"
    case grocery = "Grocery or big-box store"
    case independent = "Independent pharmacy"
    case institutional = "Hospital, clinic or health-plan pharmacy"
    case specialty = "Specialty, compounding or veterinary pharmacy"

    static func classify(_ name: String) -> PharmacyKind {
        let n = name.lowercased()
        func has(_ words: [String]) -> Bool {
            words.contains { n.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: $0), options: .regularExpression) != nil }
        }
        if has(["veterinar", "vet ", "pet ", "pets", "critter", "animal", "compounding", "infusion", "specialty",
                "nuclear", "long term care", "ltc", "oncology", "fertility", "hospice", "mail order"]) { return .specialty }
        if has(["hospital", "medical center", "clinic", "kaiser", "health system", "inova", "discharge",
                "outpatient", "university", "health center", "urgent care", "medical group"]) { return .institutional }
        if has(["cvs", "walgreens", "rite aid", "duane reade", "walmart", "costco", "sam's club", "target"]) { return .chain }
        if has(["giant", "safeway", "harris teeter", "wegmans", "kroger", "publix", "food lion", "albertsons",
                "h-e-b", "meijer", "shoprite", "stop & shop", "fred meyer", "hy-vee", "weis", "vons", "ralphs"]) { return .grocery }
        return .independent
    }
}

/// One thing that raised or lowered a pharmacy's percentage.
struct EstimateFactor: Identifiable {
    let name: String
    /// Change on the log-odds scale. Positive raises the percentage.
    let effect: Double
    let detail: String
    let source: String
    var id: String { name }

    var direction: String {
        switch effect {
        case 0.3...: return "Raises a lot"
        case 0.05..<0.3: return "Raises"
        case -0.05..<0.05: return "Neutral"
        case -0.3 ..< -0.05: return "Lowers"
        default: return "Lowers a lot"
        }
    }
}

/// The starting percentage for a pharmacy BEFORE any crowd reports, built only from public data.
///
/// It works on the "log-odds" scale so factors add up sensibly and the result always stays
/// between 0% and 100%:
///
///     logit(p) = logit(base from FDA shortage status)
///              + how commonly prescribed + controlled-substance status + number of makers
///              + recent recalls + wholesale price trend + dosage form + pharmacy type
///
/// These numbers are informed judgments, not measured probabilities. Crowd reports
/// correct them as they come in (see AvailabilityEstimator).
enum PriorModel {
    static func prior(shortage: ShortageStatus, signals: DrugSignals?, medication: Medication?, pharmacy: Pharmacy)
        -> (probability: Double, factors: [EstimateFactor]) {
        let base = baseProbability(shortage)
        var factors = [EstimateFactor(name: "FDA shortage status", effect: 0, detail: baseDetail(shortage, base), source: "FDA Drug Shortages")]

        if let signals {
            if let rx = signals.yearlyPrescriptions { factors.append(volumeFactor(rx)) }
            if let schedule = signals.deaSchedule { factors.append(contentsOf: scheduleFactor(schedule)) }
            if let makers = signals.makers { factors.append(makersFactor(makers)) }
            if let recalls = signals.recalls { factors.append(contentsOf: recallFactor(recalls)) }
            if let change = signals.priceChange { factors.append(priceFactor(change)) }
        }
        if let medication { factors.append(contentsOf: formFactor(medication)) }
        factors.append(contentsOf: pharmacyFactor(PharmacyKind.classify(pharmacy.name), inShortage: shortage.level == .active))

        let logOdds = logit(base) + factors.reduce(0) { $0 + $1.effect }
        var probability = min(0.97, max(0.03, sigmoid(logOdds)))
        // A specialty/veterinary pharmacy is unlikely to fill it no matter how common the drug is
        if PharmacyKind.classify(pharmacy.name) == .specialty { probability = min(probability, specialtyCap) }
        return (probability, factors)
    }

    static let specialtyCap = 0.15

    // MARK: - Base

    static func baseProbability(_ s: ShortageStatus) -> Double {
        switch s.level {
        case .none: return 0.88
        case .resolved: return 0.80
        case .discontinuing: return 0.60
        case .unknown: return 0.75
        case .active:
            let known = s.manufacturers.filter { $0.category != .unknown }
            guard !known.isEmpty else { return 0.50 }
            let supply = known.reduce(0.0) { $0 + ($1.category == .available ? 1 : $1.category == .limited ? 0.5 : 0) }
            return 0.30 + 0.45 * supply / Double(known.count)
        }
    }

    private static func baseDetail(_ s: ShortageStatus, _ base: Double) -> String {
        let start = "starting point \(Int((base * 100).rounded()))%"
        switch s.level {
        case .none: return "Not in an FDA shortage, \(start)"
        case .resolved: return "A past FDA shortage is resolved, \(start)"
        case .discontinuing: return "Being discontinued by a maker, \(start)"
        case .unknown: return "FDA data unavailable, \(start)"
        case .active:
            let known = s.manufacturers.filter { $0.category != .unknown }
            let ok = known.filter { $0.category == .available }.count
            return "Official FDA shortage, \(ok) of \(known.count) makers report it available, \(start)"
        }
    }

    // MARK: - Medication factors

    static func volumeFactor(_ prescriptions: Int) -> EstimateFactor {
        let effect: Double, text: String
        switch prescriptions {
        case 300_000...: effect = 0.4; text = "Very commonly prescribed, so most pharmacies keep it in stock"
        case 50_000..<300_000: effect = 0.2; text = "Commonly prescribed"
        case 5_000..<50_000: effect = -0.2; text = "Less commonly prescribed"
        case 1_000..<5_000: effect = -1.0; text = "Rarely prescribed, so pharmacies often need to order it (usually 1 to 2 days)"
        default: effect = -1.8; text = "Very rarely prescribed, so most pharmacies must special-order it"
        }
        return .init(name: "How common it is", effect: effect,
                     detail: "\(text) (\(prescriptions.formatted()) Medicaid prescriptions last year)", source: "Medicaid drug utilization")
    }

    static func scheduleFactor(_ schedule: String) -> [EstimateFactor] {
        switch schedule {
        case "CII":
            return [.init(name: "Controlled substance", effect: -0.4,
                          detail: "Schedule II: pharmacies face strict ordering limits and can't transfer it between stores", source: "FDA NDC Directory")]
        case "CIII", "CIV", "CV":
            return [.init(name: "Controlled substance", effect: -0.15,
                          detail: "Schedule \(schedule.dropFirst()): some ordering limits apply", source: "FDA NDC Directory")]
        default:
            return []
        }
    }

    static func makersFactor(_ count: Int) -> EstimateFactor {
        let effect: Double
        switch count {
        case ...1: effect = -0.25
        case 2: effect = -0.15
        case 3...5: effect = 0
        default: effect = 0.15
        }
        return .init(name: "Number of makers", effect: effect,
                     detail: count <= 1 ? "Only 1 approved product" : "\(count) separately approved products", source: "FDA NDC Directory")
    }

    static func recallFactor(_ recalls: [SupplyRiskService.Recall]) -> [EstimateFactor] {
        guard !recalls.isEmpty else { return [] }
        let serious = recalls.count >= 2 || recalls.contains { $0.classification == "Class I" }
        return [.init(name: "Recent recalls", effect: serious ? -0.4 : -0.2,
                      detail: "\(recalls.count) recall\(recalls.count == 1 ? "" : "s") in the last 6 months", source: "FDA Enforcement Reports")]
    }

    static func priceFactor(_ change: Double) -> EstimateFactor {
        let effect: Double
        switch change {
        case 0.20...: effect = -0.5
        case 0.10..<0.20: effect = -0.3
        case 0.03..<0.10: effect = -0.1
        case -0.03..<0.03: effect = 0
        default: effect = 0.1
        }
        let percent = Int((change * 100).rounded())
        let text = percent == 0 ? "flat" : (percent > 0 ? "up \(percent)%" : "down \(-percent)%")
        return .init(name: "Wholesale price trend", effect: effect,
                     detail: "Price pharmacies pay is \(text) over ~3 months", source: "Medicaid NADAC")
    }

    static func formFactor(_ medication: Medication) -> [EstimateFactor] {
        switch medication.formRank {
        case 3: return [.init(name: "Form", effect: -0.2, detail: "Injectables and patches are stocked less widely than tablets", source: "RxNorm")]
        case 2: return [.init(name: "Form", effect: -0.1, detail: "Liquids are stocked a little less widely than tablets", source: "RxNorm")]
        default: return []
        }
    }

    // MARK: - Pharmacy factor

    static func pharmacyFactor(_ kind: PharmacyKind, inShortage: Bool) -> [EstimateFactor] {
        let source = "Pharmacy name"
        switch kind {
        case .specialty:
            return [.init(name: "Pharmacy type", effect: -2.0, detail: "\(kind.rawValue): usually doesn't fill regular prescriptions (capped at \(Int(specialtyCap * 100))%)", source: source)]
        case .institutional:
            return [.init(name: "Pharmacy type", effect: -0.5, detail: "\(kind.rawValue): may only serve its own patients or members", source: source)]
        case .chain, .grocery:
            return inShortage ? [] : [.init(name: "Pharmacy type", effect: 0.1, detail: "\(kind.rawValue) with frequent deliveries", source: source)]
        case .independent:
            return inShortage ? [.init(name: "Pharmacy type", effect: 0.15,
                                       detail: "\(kind.rawValue): uses different suppliers, which sometimes helps during shortages", source: source)] : []
        }
    }

    // MARK: - Math

    static func logit(_ p: Double) -> Double { log(p / (1 - p)) }
    static func sigmoid(_ x: Double) -> Double { 1 / (1 + exp(-x)) }
}
