import Foundation

/// A commonly-needed medication shown in the home screen's "Shortage Watch".
struct WatchedDrug: Identifiable, Hashable {
    let id: String
    let title: String          // what people call it, e.g. "Adderall"
    let subtitle: String       // generic name, e.g. "amphetamine salts"
    let fdaTerm: String        // word to look for in FDA generic names
    let searchQuery: String    // what to search when tapped

    /// Medications people often struggle to find. Status is checked live against the FDA.
    static let featured: [WatchedDrug] = [
        WatchedDrug(id: "adderall", title: "Adderall", subtitle: "amphetamine salts", fdaTerm: "amphetamine aspartate", searchQuery: "Adderall"),
        WatchedDrug(id: "vyvanse", title: "Vyvanse", subtitle: "lisdexamfetamine", fdaTerm: "lisdexamfetamine", searchQuery: "Vyvanse"),
        WatchedDrug(id: "methylphenidate", title: "Ritalin / Concerta", subtitle: "methylphenidate", fdaTerm: "methylphenidate", searchQuery: "methylphenidate"),
        WatchedDrug(id: "amoxicillin", title: "Amoxicillin", subtitle: "antibiotic", fdaTerm: "amoxicillin", searchQuery: "amoxicillin"),
        WatchedDrug(id: "albuterol", title: "Albuterol", subtitle: "asthma inhaler", fdaTerm: "albuterol", searchQuery: "albuterol"),
        WatchedDrug(id: "semaglutide", title: "Ozempic / Wegovy", subtitle: "semaglutide", fdaTerm: "semaglutide", searchQuery: "Ozempic"),
    ]
}

/// FDA shortage status for a whole medication (all strengths and forms).
struct DrugShortageSummary {
    /// Products (manufacturer packages) with a current shortage listing
    let listedProducts: Int
    let limited: Int
    let unavailable: Int
    let lastUpdated: Date?

    var inShortage: Bool { listedProducts > 0 }
    var headline: String {
        guard inShortage else { return "No FDA shortage" }
        let short = limited + unavailable
        return short > 0 ? "Shortage · \(short) of \(listedProducts) products limited" : "Shortage listed"
    }
}

/// Reads the FDA Drug Shortages database (openFDA) for the Shortage Watch card.
struct ShortageWatchService {
    func summary(for drug: WatchedDrug) async throws -> DrugShortageSummary {
        let term = drug.fdaTerm.replacingOccurrences(of: " ", with: "+")
        let search = "generic_name:%22\(term)%22+AND+status:%22Current%22"
        guard let url = URL(string: "https://api.fda.gov/drug/shortages.json?search=\(search)&limit=1000") else {
            return DrugShortageSummary(listedProducts: 0, limited: 0, unavailable: 0, lastUpdated: nil)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        // openFDA answers 404 when there are no matching records = no current shortage
        if (response as? HTTPURLResponse)?.statusCode == 404 {
            return DrugShortageSummary(listedProducts: 0, limited: 0, unavailable: 0, lastUpdated: nil)
        }
        struct Response: Decodable { let results: [ShortageRecord]? }
        let records = try JSONDecoder().decode(Response.self, from: data).results ?? []
        let categories = records.map { FDAShortageService.category($0.availability) }
        return DrugShortageSummary(
            listedProducts: records.count,
            limited: categories.filter { $0 == .limited }.count,
            unavailable: categories.filter { $0 == .unavailable }.count,
            lastUpdated: records.compactMap { FDAShortageService.date($0.update_date) }.max()
        )
    }
}
