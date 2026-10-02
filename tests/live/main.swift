// MedBeam live tests: real data sources. Needs internet. Run with:  ./tests/run.sh live
import Foundation
import MapKit

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { passed += 1; print("ok    \(name)  \(detail)") } else { failed += 1; print("FAIL  \(name)  \(detail)") }
}
let rx = RxNormService(), fda = FDAShortageService(), risk = SupplyRiskService(), places = PharmacySearchService()

print("— Medication search (RxNorm)")
for (query, expect) in [("adderall xr 20", "Adderall XR 20 mg"), ("adderal 20", "Adderall 20 mg"), ("amoxicillin 500", "amoxicillin 500 mg"),
                        ("lisinopril 10", "lisinopril 10 mg"), ("vyvanse 30", "Vyvanse 30 mg")] {
    let r = (try? await rx.search(query)) ?? []
    check("search '\(query)'", r.first?.shortName.lowercased().hasPrefix(expect.lowercased()) == true, r.first?.shortName ?? "no results")
}
check("nonsense returns nothing", ((try? await rx.search("xyzqqq")) ?? []).isEmpty)
check("typo is corrected", !((try? await rx.search("amoxicilin")) ?? []).isEmpty)

print("— FDA status, supply risk and percentages")
let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 39, longitude: -77.5)))
let cvs = Pharmacy(id: "c", name: "CVS Pharmacy", address: "", phone: nil, url: nil, coordinate: .init(latitude: 39, longitude: -77.5), distanceMiles: 1, mapItem: item)
var percents: [String: Double] = [:]
for query in ["adderall 20", "adderall xr 20", "amoxicillin 500 capsule", "lisinopril 10", "vyvanse 30 capsule", "insulin glargine", "albuterol 0.09", "edaravone"] {
    guard let med = try? await rx.search(query).first, let d = try? await rx.details(for: med) else { check("lookup \(query)", false); continue }
    let s = await fda.status(for: d)
    async let r = risk.risk(for: d, shortage: s)
    async let v = risk.yearlyPrescriptions(rxcuis: d.relatedRxcuis)
    var signals = await r.signals
    signals.yearlyPrescriptions = await v
    let e = AvailabilityEstimator.estimate(for: cvs, shortage: s, signals: signals, medication: med, reports: [])
    percents[query] = e.probability
    check("\(med.shortName)", s.level != .unknown && (0.03...0.97).contains(e.probability) && e.factors.count >= 2,
          "→ \(e.percentText) at a chain | FDA: \(s.headline) | risk \(await r.level.rawValue) | Rx/yr \(signals.yearlyPrescriptions.map { "\($0)" } ?? "n/a") | \(e.factors.count) factors")
}
if let a = percents["adderall 20"], let b = percents["amoxicillin 500 capsule"] {
    check("a drug in FDA shortage scores below a common antibiotic", a < b, "\(Int(a * 100))% vs \(Int(b * 100))%")
}
if let a = percents["edaravone"], let b = percents["lisinopril 10"] {
    check("a rare specialty drug scores below a common one", a < b, "\(Int(a * 100))% vs \(Int(b * 100))%")
}

print("— ZIP codes and pharmacy search (Apple Maps)")
for (zip, minimum) in [("20105", 5), ("20147", 10), ("10001", 15), ("90210", 10), ("60601", 15), ("99501", 5), ("96813", 10), ("04736", 1), ("59301", 1)] {
    try? await Task.sleep(for: .seconds(2.5))   // Apple limits how fast apps can search
    do {
        let c = try await places.coordinate(forZIP: zip)
        let found = try await places.pharmacies(near: c)
        let names = Set(found.pharmacies.map { "\($0.name)|\($0.address)" })
        check("ZIP \(zip)", found.pharmacies.count >= minimum && names.count == found.pharmacies.count
              && found.pharmacies.allSatisfy { $0.distanceMiles <= found.radiusMiles },
              "\(found.pharmacies.count) pharmacies within \(Int(found.radiusMiles)) mi, nearest \(String(format: "%.1f", found.pharmacies.first?.distanceMiles ?? -1)) mi, no duplicates")
    } catch { check("ZIP \(zip)", false, error.localizedDescription) }
}
for zip in ["00000", "99999"] {
    try? await Task.sleep(for: .seconds(2.5))
    do { _ = try await places.coordinate(forZIP: zip); check("fake ZIP \(zip) rejected", false, "was accepted") }
    catch { check("fake ZIP \(zip) rejected", error.localizedDescription.contains("couldn't find"), error.localizedDescription) }
}

print("— Community database (read-only check)")
if let service = CommunityReportService.configured() {
    do {
        let r = try await service.fetch(rxcui: "861226", near: .init(latitude: 38.96, longitude: -77.61), radiusMiles: 10)
        check("community database reachable", true, "\(r.count) reports near Aldie for Adderall XR 20")
    } catch { check("community database reachable", false, error.localizedDescription) }
} else { check("community database configured", false) }

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
