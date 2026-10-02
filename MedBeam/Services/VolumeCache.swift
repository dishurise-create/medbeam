import Foundation

/// Remembers prescription-volume lookups (they take ~15 seconds) for 30 days.
enum VolumeCache {
    private static let key = "rxVolumeCache"
    private static let maxAge: TimeInterval = 30 * 86_400

    static func get(_ rxcui: String) -> Int? {
        guard let all = UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]],
              let entry = all[rxcui], entry.count == 2,
              Date.now.timeIntervalSince1970 - entry[1] < maxAge else { return nil }
        return Int(entry[0])
    }

    static func set(_ count: Int, for rxcui: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] ?? [:]
        all[rxcui] = [Double(count), Date.now.timeIntervalSince1970]
        UserDefaults.standard.set(all, forKey: key)
    }
}
