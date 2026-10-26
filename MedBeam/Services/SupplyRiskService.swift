import Foundation

/// Raw facts about a medication, from public data. Used by both the supply risk score
/// and the per-pharmacy availability estimate. `nil` = that source had no data.
struct DrugSignals {
    /// Separately approved products (≈ number of makers)
    var makers: Int?
    var recalls: [SupplyRiskService.Recall]?
    /// Change in the price pharmacies pay over ~3 months (0.12 = +12%)
    var priceChange: Double?
    /// DEA schedule, e.g. "CII" for Adderall. Empty string = not a controlled substance.
    var deaSchedule: String?
    /// Prescriptions filled nationally through Medicaid last year: how commonly it's dispensed
    var yearlyPrescriptions: Int?
}

/// A national "how fragile is the supply of this medication?" score, built only from public data.
/// It describes the medication as a whole — it can NOT say whether one pharmacy has it in stock.
struct SupplyRisk {
    enum Level: String {
        case low = "Low", moderate = "Moderate", elevated = "Elevated", high = "High"
    }

    struct Factor: Identifiable {
        let name: String
        /// 0 = no risk, 1 = high risk
        let risk: Double
        let weight: Double
        let detail: String
        let source: String
        var id: String { name }
    }

    let factors: [Factor]
    var signals = DrugSignals()

    /// True when the FDA officially lists this medication as in shortage.
    let officialShortage: Bool
    /// Data sources that had no data for this medication (e.g. not in the price survey)
    let unavailableSources: [String]

    /// Weighted average of the factors we could get data for (0...1).
    /// An official FDA shortage always counts as at least "Elevated".
    var score: Double {
        let totalWeight = factors.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        let average = factors.reduce(0) { $0 + $1.risk * $1.weight } / totalWeight
        return officialShortage ? max(average, 0.5) : average
    }

    var level: Level {
        switch score {
        case ..<0.25: return .low
        case ..<0.5: return .moderate
        case ..<0.75: return .elevated
        default: return .high
        }
    }

    /// 0–100 for display
    var points: Int { Int((score * 100).rounded()) }
}

/// Combines four free government data sources:
/// 1. FDA Drug Shortages — is there an official shortage?
/// 2. FDA NDC Directory — how many separately approved products (makers) exist?
/// 3. FDA Enforcement Reports — any recalls in the last 6 months?
/// 4. Medicaid NADAC — is the price pharmacies pay rising (a sign of tight supply)?
struct SupplyRiskService {
    static let weights = (shortage: 0.45, makers: 0.20, recalls: 0.15, price: 0.20)

    func risk(for details: MedicationDetails, shortage: ShortageStatus) async -> SupplyRisk {
        let rxcuis = details.relatedRxcuis
        async let makers = approvedProductCount(rxcuis: rxcuis)
        async let recalls = recentRecalls(rxcuis: rxcuis)
        async let price = priceChange(rxcuis: rxcuis)

        var factors: [SupplyRisk.Factor] = []
        var missing: [String] = []
        var signals = DrugSignals()
        if let f = Self.shortageFactor(shortage) { factors.append(f) } else { missing.append("FDA Drug Shortages") }
        if let product = await makers {
            factors.append(Self.makersFactor(product.count))
            signals.makers = product.count
            signals.deaSchedule = product.schedule
        } else { missing.append("FDA NDC Directory") }
        if let recallList = await recalls {
            factors.append(Self.recallFactor(recallList))
            signals.recalls = recallList
        } else { missing.append("FDA Enforcement Reports") }
        if let change = await price {
            factors.append(Self.priceFactor(change))
            signals.priceChange = change
        } else { missing.append("Medicaid NADAC price survey") }
        return SupplyRisk(factors: factors, signals: signals,
                          officialShortage: shortage.level == .active, unavailableSources: missing)
    }

    // MARK: - Scoring (kept separate so it can be tested)

    static func shortageFactor(_ s: ShortageStatus) -> SupplyRisk.Factor? {
        let risk: Double
        let detail: String
        switch s.level {
        case .unknown:
            return nil
        case .none:
            risk = 0; detail = "Not listed in the FDA shortage database"
        case .resolved:
            risk = 0.2; detail = "A past FDA shortage was resolved"
        case .discontinuing:
            risk = 0.5; detail = "At least one maker is discontinuing it"
        case .active:
            let known = s.manufacturers.filter { $0.category != .unknown }
            let short = known.filter { $0.category != .available }.count
            let fraction = known.isEmpty ? 0.5 : Double(short) / Double(known.count)
            risk = 0.5 + 0.5 * fraction
            detail = known.isEmpty ? "Official FDA shortage"
                : "Official FDA shortage · \(short) of \(known.count) makers limited or unavailable"
        }
        return .init(name: "FDA shortage status", risk: risk, weight: weights.shortage, detail: detail, source: "FDA Drug Shortages")
    }

    static func makersFactor(_ count: Int) -> SupplyRisk.Factor {
        let risk: Double
        switch count {
        case ...1: risk = 0.8
        case 2: risk = 0.6
        case 3: risk = 0.4
        case 4...5: risk = 0.25
        default: risk = 0.1
        }
        let detail = count <= 1
            ? "Only 1 approved product (often a brand with no generic), so one supply problem affects everyone"
            : "\(count) separately approved products. More makers means a safer supply"
        return .init(name: "Number of makers", risk: risk, weight: weights.makers, detail: detail, source: "FDA NDC Directory")
    }

    struct Recall { let date: Date; let firm: String; let classification: String }

    static func recallFactor(_ recalls: [Recall]) -> SupplyRisk.Factor {
        let serious = recalls.contains { $0.classification == "Class I" }
        let risk: Double = recalls.isEmpty ? 0 : (recalls.count >= 2 || serious ? 0.8 : 0.5)
        let detail: String
        if let latest = recalls.max(by: { $0.date < $1.date }) {
            detail = "\(recalls.count) recall\(recalls.count == 1 ? "" : "s") in the last 6 months · latest: \(latest.firm), \(latest.date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            detail = "No recalls in the last 6 months"
        }
        return .init(name: "Recent recalls", risk: risk, weight: weights.recalls, detail: detail, source: "FDA Enforcement Reports")
    }

    /// `change` = price change over ~3 months, e.g. 0.12 = +12%
    static func priceFactor(_ change: Double) -> SupplyRisk.Factor {
        let risk: Double
        switch change {
        case 0.20...: risk = 0.9
        case 0.10..<0.20: risk = 0.6
        case 0.03..<0.10: risk = 0.3
        case -0.03..<0.03: risk = 0.1
        default: risk = 0
        }
        let percent = Int((change * 100).rounded())
        let arrow = percent > 0 ? "up" : (percent < 0 ? "down" : "flat")
        let detail = percent == 0 ? "Pharmacy purchase price unchanged over ~3 months"
            : "Pharmacy purchase price \(arrow) \(abs(percent))% over ~3 months"
        return .init(name: "Wholesale price trend", risk: risk, weight: weights.price, detail: detail, source: "Medicaid NADAC")
    }

    // MARK: - Data fetching (each returns nil if the data isn't available)

    /// Rows from a Medicaid dataset whose NDC is in `ndcs`.
    private func medicaidRows(dataset: String, ndcs: [String], extra: [URLQueryItem] = [],
                              limit: Int, timeout: TimeInterval = 60) async -> [[String: Any]]? {
        var components = URLComponents(string: "https://data.medicaid.gov/api/1/datastore/query/\(dataset)/0")!
        components.queryItems = [URLQueryItem(name: "conditions[0][property]", value: "ndc"),
                                 URLQueryItem(name: "conditions[0][operator]", value: "in"),
                                 URLQueryItem(name: "limit", value: "\(limit)")]
            + extra
            + ndcs.map { URLQueryItem(name: "conditions[0][value][]", value: $0) }
        guard let url = components.url, let json = await fetchJSON(url, timeout: timeout) else { return nil }
        return json["results"] as? [[String: Any]]
    }

    /// openFDA results. Empty when nothing matches (openFDA answers 404), nil if the request failed.
    private func openFDAResults(_ url: URL) async -> [[String: Any]]? {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 404 { return [] }
        guard status == 200, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return json["results"] as? [[String: Any]]
    }

    private func rxcuiQuery(_ rxcuis: [String]) -> String {
        "(" + rxcuis.map { "openfda.rxcui:%22\($0)%22" }.joined(separator: "+") + ")"
    }

    /// Distinct FDA application numbers = distinct approved products (repackagers share the original's number).
    private func approvedProductCount(rxcuis: [String]) async -> (count: Int, schedule: String)? {
        guard let url = URL(string: "https://api.fda.gov/drug/ndc.json?search=\(rxcuiQuery(rxcuis))&limit=1000"),
              let results = await openFDAResults(url), !results.isEmpty else { return nil }
        let applications = Set(results.compactMap { $0["application_number"] as? String })
        guard !applications.isEmpty else { return nil }
        // DEA schedule ("CII", "CIII", ...) — missing means not a controlled substance
        let schedule = results.compactMap { $0["dea_schedule"] as? String }.first ?? ""
        return (applications.count, schedule)
    }

    private func recentRecalls(rxcuis: [String]) async -> [Recall]? {
        let f = DateFormatter.fixed("yyyyMMdd")
        let from = f.string(from: Date.now.addingTimeInterval(-182 * 86_400))
        let to = f.string(from: .now)
        let search = "\(rxcuiQuery(rxcuis))+AND+report_date:%5B\(from)+TO+\(to)%5D"
        guard let url = URL(string: "https://api.fda.gov/drug/enforcement.json?search=\(search)&limit=100"),
              let results = await openFDAResults(url) else { return nil }
        return results.compactMap { r in
            guard let dateText = r["report_date"] as? String, let date = f.date(from: dateText) else { return nil }
            return Recall(date: date, firm: r["recalling_firm"] as? String ?? "Unknown",
                          classification: r["classification"] as? String ?? "")
        }
    }

    /// RxNorm → NDC product codes (the IDs Medicaid data is organized by)
    private func ndcCodes(rxcuis: [String], limit: Int) async -> [String] {
        let ndcs: [String] = await withTaskGroup(of: [String].self) { group in
            for rxcui in rxcuis.prefix(12) {
                group.addTask {
                    guard let url = URL(string: "https://rxnav.nlm.nih.gov/REST/rxcui/\(rxcui)/ndcs.json"),
                          let json = await fetchJSON(url),
                          let list = ((json["ndcGroup"] as? [String: Any])?["ndcList"] as? [String: Any])?["ndc"] as? [String]
                    else { return [] }
                    return list
                }
            }
            var all: [String] = []
            for await list in group { all += list }
            return all
        }
        return Array(Set(ndcs)).sorted().prefix(limit).map { $0 }
    }

    /// How many prescriptions for this medication Medicaid paid for nationally last year.
    /// A measure of how commonly pharmacies dispense (and therefore stock) it. Slow (~15 s),
    /// so results are cached by the caller.
    func yearlyPrescriptions(rxcuis: [String]) async -> Int? {
        // Count brand AND generic versions (e.g. insulin glargine = Lantus, Basaglar, ...)
        let all = await withBrandAndGenericEquivalents(rxcuis)
        let ndcs = await ndcCodes(rxcuis: all, limit: 150)
        guard !ndcs.isEmpty, let dataset = await MedicaidDatasets.shared.utilizationDataset() else { return nil }
        let national = [URLQueryItem(name: "conditions[1][property]", value: "state"),
                        URLQueryItem(name: "conditions[1][value]", value: "XX")]   // XX = national totals
        guard let rows = await medicaidRows(dataset: dataset, ndcs: ndcs, extra: national, limit: 3000, timeout: 45)
        else { return nil }
        let total = rows.reduce(0.0) { $0 + (Double($1["number_of_prescriptions"] as? String ?? "") ?? 0) }
        // Zero almost always means the product codes didn't match, not that nobody takes it
        return total > 0 ? Int(total) : nil
    }

    /// Adds the brand-name (SBD) and generic (SCD) versions of the same drug + strength.
    private func withBrandAndGenericEquivalents(_ rxcuis: [String]) async -> [String] {
        let related: [String] = await withTaskGroup(of: [String].self) { group in
            for rxcui in rxcuis.prefix(4) {
                group.addTask {
                    guard let url = URL(string: "https://rxnav.nlm.nih.gov/REST/rxcui/\(rxcui)/related.json?tty=SBD+SCD"),
                          let json = await fetchJSON(url),
                          let groups = (json["relatedGroup"] as? [String: Any])?["conceptGroup"] as? [[String: Any]] else { return [] }
                    return groups.flatMap { ($0["conceptProperties"] as? [[String: Any]] ?? []).compactMap { $0["rxcui"] as? String } }
                }
            }
            var all: [String] = []
            for await list in group { all += list }
            return all
        }
        return Array(Set(rxcuis + related))
    }

    /// Price change over about 3 months, from the weekly NADAC survey.
    private func priceChange(rxcuis: [String]) async -> Double? {
        let ndcs = await ndcCodes(rxcuis: rxcuis, limit: 60)
        guard !ndcs.isEmpty, let datasets = await MedicaidDatasets.shared.latestTwo() else { return nil }

        // 2. Weekly prices for those NDCs. This year first; last year only if needed (early in the year).
        var byDate: [String: [Double]] = [:]
        for dataset in datasets {
            if Self.threeMonthChange(byDate) != nil { break }
            guard let rows = await medicaidRows(dataset: dataset, ndcs: ndcs, limit: 1500) else { continue }
            for row in rows {
                guard let date = row["effective_date"] as? String,
                      let price = Double(row["nadac_per_unit"] as? String ?? "") else { continue }
                byDate[date, default: []].append(price)
            }
        }
        return Self.threeMonthChange(byDate)
    }

    /// Compares the latest average price with the average ~90 days earlier.
    static func threeMonthChange(_ byDate: [String: [Double]]) -> Double? {
        let f = DateFormatter.fixed("yyyy-MM-dd")
        let points = byDate.compactMap { key, prices -> (Date, Double)? in
            guard let date = f.date(from: key), !prices.isEmpty else { return nil }
            return (date, prices.reduce(0, +) / Double(prices.count))
        }.sorted { $0.0 < $1.0 }
        guard let latest = points.last,
              let baseline = points.last(where: { $0.0 <= latest.0.addingTimeInterval(-84 * 86_400) }),
              baseline.1 > 0 else { return nil }
        return latest.1 / baseline.1 - 1
    }
}

/// Downloads a JSON object. Returns nil on any error or non-200 response.
func fetchJSON(_ url: URL, timeout: TimeInterval = 60) async -> [String: Any]? {
    var request = URLRequest(url: url)
    request.timeoutInterval = timeout
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

/// Finds the current Medicaid datasets (a new one is published each year).
actor MedicaidDatasets {
    static let shared = MedicaidDatasets()
    private var nadac: [String]?
    private var utilization: String?

    /// "State Drug Utilization Data" for the most recent complete year.
    func utilizationDataset() async -> String? {
        if let utilization { return utilization }
        let yearly = await datasets(search: "State%20Drug%20Utilization%20Data", titlePrefix: "State Drug Utilization Data ")
        // Prefer last year (complete); this year's data is still filling in
        let thisYear = Calendar.current.component(.year, from: .now)
        utilization = (yearly.first { $0.year < thisYear } ?? yearly.first)?.id
        return utilization
    }

    /// The two newest NADAC price datasets (this year and last).
    func latestTwo() async -> [String]? {
        if let nadac { return nadac }
        let yearly = await datasets(search: "National%20Average%20Drug%20Acquisition%20Cost",
                                    titlePrefix: "NADAC (National Average Drug Acquisition Cost) ")
        let ids = yearly.prefix(2).map(\.id)
        nadac = ids.isEmpty ? nil : ids
        return nadac
    }

    /// Datasets titled "<titlePrefix><year>", newest first.
    private func datasets(search: String, titlePrefix: String) async -> [(year: Int, id: String)] {
        guard let url = URL(string: "https://data.medicaid.gov/api/1/search?fulltext=\(search)&page-size=40"),
              let json = await fetchJSON(url),
              let results = json["results"] as? [String: [String: Any]] else { return [] }
        return results.values.compactMap { item -> (year: Int, id: String)? in
            guard let title = item["title"] as? String, title.hasPrefix(titlePrefix),
                  let year = Int(title.dropFirst(titlePrefix.count)),
                  let id = item["identifier"] as? String else { return nil }
            return (year, id)
        }.sorted { $0.year > $1.year }
    }
}
