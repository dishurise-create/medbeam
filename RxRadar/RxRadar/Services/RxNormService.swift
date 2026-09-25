import Foundation

/// Talks to the free RxNorm API from the National Library of Medicine.
/// Docs: https://lhncbc.nlm.nih.gov/RxNav/APIs/RxNormAPIs.html (no API key needed)
struct RxNormService {
    private let base = "https://rxnav.nlm.nih.gov/REST"

    /// Searches for medication products. "adderall xr 20" searches "adderall",
    /// then keeps only results containing "xr" and "20".
    func search(_ query: String) async throws -> [Medication] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard let firstWord = words.first else { return [] }

        var results = try await drugs(named: query)
        if results.isEmpty {
            results = try await drugs(named: firstWord)
        }
        if results.isEmpty, let suggestion = try await spellingSuggestion(for: firstWord) {
            results = try await drugs(named: suggestion)
        }

        let filters = words.dropFirst()
        let filtered = results.filter { med in
            let text = (med.displayName + " " + med.name).lowercased()
            return filters.allSatisfy { text.contains($0) }
        }
        // Best matches first: names that start with what was typed, then single-ingredient
        // products, then brand names, then alphabetical (natural number order: 5 mg < 10 mg).
        return filtered.sorted { a, b in
            let aStarts = a.shortName.lowercased().hasPrefix(firstWord)
            let bStarts = b.shortName.lowercased().hasPrefix(firstWord)
            if aStarts != bStarts { return aStarts }
            let aCombo = a.name.contains(" / "), bCombo = b.name.contains(" / ")
            if aCombo != bCombo { return !aCombo }
            if a.formRank != b.formRank { return a.formRank < b.formRank }
            if a.isBrand != b.isBrand { return a.isBrand }
            return a.shortName.localizedStandardCompare(b.shortName) == .orderedAscending
        }
    }

    /// Looks up ingredients and generic equivalents, used to match FDA shortage records.
    func details(for med: Medication) async throws -> MedicationDetails {
        let url = URL(string: "\(base)/rxcui/\(med.rxcui)/related.json?tty=IN+SCD")!
        let response: RelatedResponse = try await fetch(url)
        let groups = response.relatedGroup.conceptGroup ?? []
        let ingredients = groups.first { $0.tty == "IN" }?.conceptProperties?.map(\.name) ?? []
        let generics = groups.first { $0.tty == "SCD" }?.conceptProperties ?? []
        let genericName = med.termType == "SCD" ? med.name : (generics.first?.name ?? med.name)
        return MedicationDetails(
            medication: med,
            ingredients: ingredients,
            relatedRxcuis: [med.rxcui] + generics.map(\.rxcui),
            genericName: genericName
        )
    }

    // MARK: - Private

    private func drugs(named name: String) async throws -> [Medication] {
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/drugs.json?name=\(encoded)") else { return [] }
        let response: DrugsResponse = try await fetch(url)
        let groups = response.drugGroup.conceptGroup ?? []
        return groups
            .filter { $0.tty == "SBD" || $0.tty == "SCD" }
            .flatMap { $0.conceptProperties ?? [] }
            .map { concept in
                let synonym = concept.synonym ?? ""
                return Medication(
                    rxcui: concept.rxcui,
                    name: concept.name,
                    displayName: synonym.isEmpty ? concept.name : synonym,
                    termType: concept.tty ?? "SCD"
                )
            }
    }

    private func spellingSuggestion(for word: String) async throws -> String? {
        guard let encoded = word.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(base)/spellingsuggestions.json?name=\(encoded)") else { return nil }
        let response: SpellingResponse = try await fetch(url)
        return response.suggestionGroup.suggestionList?.suggestion?.first
    }

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - JSON shapes

private struct Concept: Decodable {
    let rxcui: String
    let name: String
    let synonym: String?
    let tty: String?
}

private struct ConceptGroup: Decodable {
    let tty: String?
    let conceptProperties: [Concept]?
}

private struct DrugsResponse: Decodable {
    struct Group: Decodable { let conceptGroup: [ConceptGroup]? }
    let drugGroup: Group
}

private struct RelatedResponse: Decodable {
    struct Group: Decodable { let conceptGroup: [ConceptGroup]? }
    let relatedGroup: Group
}

private struct SpellingResponse: Decodable {
    struct List: Decodable { let suggestion: [String]? }
    struct Group: Decodable { let suggestionList: List? }
    let suggestionGroup: Group
}
