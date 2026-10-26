import Foundation

/// Reads the official FDA Drug Shortages database through openFDA.
/// Docs: https://open.fda.gov/apis/drug/drugshortages/ (free, no key needed for light use)
///
/// Each FDA record is one manufacturer's package of a drug, with that manufacturer's
/// availability ("Available", "Limited Availability", "Unavailable") and a status
/// ("Current", "Resolved", "To Be Discontinued").
struct FDAShortageService {
    private let base = "https://api.fda.gov/drug/shortages.json"

    /// Never throws: if the FDA can't be reached, returns `.unknown` so the app still works.
    func status(for details: MedicationDetails) async -> ShortageStatus {
        var records: [ShortageRecord] = []

        // 1. Exact match on RxNorm IDs (most precise)
        let rxcuiTerms = details.relatedRxcuis.map { "openfda.rxcui:%22\($0)%22" }.joined(separator: "+")
        // 2. Match by ingredient name (catches records the FDA didn't tag with RxNorm IDs)
        let ingredientTerm = details.ingredients.first.map { "generic_name:%22\(Self.encode($0))%22" }

        do {
            records += try await fetch(search: rxcuiTerms)
            if let ingredientTerm {
                records += try await fetch(search: ingredientTerm)
            }
        } catch {
            return .unknown()
        }

        var seen = Set<String>()
        let matching = records.filter { record in
            let key = record.package_ndc ?? UUID().uuidString
            guard seen.insert(key).inserted else { return false }
            return Self.matches(record, details)
        }
        return Self.summarize(matching)
    }

    // MARK: - Matching

    /// Keeps only FDA records with the same ingredients, strength and dosage form.
    static func matches(_ record: ShortageRecord, _ details: MedicationDetails) -> Bool {
        let fdaText = [record.generic_name, record.dosage_form, record.presentation]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        let medText = details.genericName.lowercased()

        for ingredient in details.ingredients where !containsWord(ingredient.lowercased(), in: fdaText) {
            return false
        }

        let medIsExtended = medText.contains("extended release") || medText.contains("24 hr") || medText.contains("12 hr")
        if medIsExtended != fdaText.contains("extended") { return false }

        let forms = ["capsule", "tablet", "injection", "solution", "suspension", "patch", "cream", "inhal", "powder"]
        if let form = forms.first(where: { medText.contains($0) }), !fdaText.contains(form) {
            if !(form == "injection" && fdaText.contains("inject")) { return false }
        }

        if let strength = strength(in: details.genericName) {
            let presentation = (record.presentation ?? "").lowercased()
            if !presentation.isEmpty && !containsWord(strength, in: presentation) { return false }
        }
        return true
    }

    /// First strength in an RxNorm name, lowercased: "5 mg", "0.5 mg/ml", "100 mcg"
    static func strength(in rxNormName: String) -> String? {
        let pattern = #"(\d+(?:\.\d+)?) (MG|MCG|UNT|MEQ)(/ML)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: rxNormName, range: NSRange(rxNormName.startIndex..., in: rxNormName)),
              let range = Range(match.range, in: rxNormName) else { return nil }
        return rxNormName[range].lowercased()
    }

    /// Word-boundary match so "5 mg" doesn't match "15 mg", and "methylphenidate" doesn't match "dexmethylphenidate".
    static func containsWord(_ word: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        let pattern = #"(?<![\w.])"# + escaped + #"(?![\w])"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Summarizing

    static func summarize(_ records: [ShortageRecord]) -> ShortageStatus {
        let current = records.filter { $0.status == "Current" }
        let level: ShortageStatus.Level
        let relevant: [ShortageRecord]
        if !current.isEmpty {
            level = .active; relevant = current
        } else if records.contains(where: { $0.status == "To Be Discontinued" }) {
            level = .discontinuing; relevant = records.filter { $0.status == "To Be Discontinued" }
        } else if records.contains(where: { $0.status == "Resolved" }) {
            level = .resolved; relevant = records
        } else {
            level = .none; relevant = []
        }

        // One row per manufacturer, keeping its most recent update
        var byCompany: [String: ShortageRecord] = [:]
        for record in relevant {
            let company = record.company_name ?? "Unknown manufacturer"
            if let existing = byCompany[company],
               (date(existing.update_date) ?? .distantPast) >= (date(record.update_date) ?? .distantPast) {
                continue
            }
            byCompany[company] = record
        }
        let manufacturers = byCompany.map { company, record in
            ManufacturerSupply(company: company, category: category(record.availability))
        }.sorted { $0.company < $1.company }

        return ShortageStatus(
            level: level,
            manufacturers: manufacturers,
            initialPostingDate: relevant.compactMap { date($0.initial_posting_date) }.min(),
            lastUpdated: relevant.compactMap { date($0.update_date) }.max(),
            fetchedAt: .now
        )
    }

    static func category(_ availability: String?) -> ManufacturerSupply.Category {
        guard let text = availability?.lowercased() else { return .unknown }
        if text.contains("unavailable") { return .unavailable }
        if text.contains("limited") { return .limited }
        if text.contains("available") { return .available }
        return .unknown
    }

    private static let dateFormatter = DateFormatter.fixed("MM/dd/yyyy")

    static func date(_ text: String?) -> Date? {
        text.flatMap { dateFormatter.date(from: $0) }
    }

    // MARK: - Networking

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics)?.replacingOccurrences(of: "%20", with: "+") ?? text
    }

    private func fetch(search: String) async throws -> [ShortageRecord] {
        guard let url = URL(string: "\(base)?search=\(search)&limit=100") else { return [] }
        return try await Self.records(url)
    }

    /// Downloads shortage records. openFDA answers 404 when nothing matches, which just means "no records".
    static func records(_ url: URL) async throws -> [ShortageRecord] {
        let (data, response) = try await URLSession.shared.data(from: url)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return [] }
        return try JSONDecoder().decode(ShortageResponse.self, from: data).results ?? []
    }
}

extension DateFormatter {
    /// A formatter for a fixed date format like "yyyy-MM-dd" (not affected by the phone's region).
    static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = format
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }
}

struct ShortageRecord: Decodable {
    let package_ndc: String?
    let generic_name: String?
    let company_name: String?
    let availability: String?
    let status: String?
    let dosage_form: String?
    let presentation: String?
    let update_date: String?
    let initial_posting_date: String?
}

private struct ShortageResponse: Decodable {
    let results: [ShortageRecord]?
}
