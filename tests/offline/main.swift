// MedBeam offline tests: the math and logic, no internet needed.
// Run with:  ./tests/run.sh
import Foundation
import MapKit

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool, _ detail: String = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL  \(name)  \(detail)") }
}
func section(_ title: String) { print("— \(title)") }

let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 39, longitude: -77.5)))
func pharmacy(_ id: String, name: String? = nil, lat: Double = 39, lon: Double = -77.5) -> Pharmacy {
    Pharmacy(id: id, name: name ?? id, address: "", phone: nil, url: nil, coordinate: .init(latitude: lat, longitude: lon), distanceMiles: 1, mapItem: item)
}
func report(_ p: Pharmacy, _ yes: Bool, daysAgo: Double, rx: String = "1", simulated: Bool = false) -> AvailabilityReport {
    AvailabilityReport(id: UUID(), rxcui: rx, pharmacyID: p.id, latitude: p.coordinate.latitude, longitude: p.coordinate.longitude,
                       result: yes ? .inStock : .outOfStock, timestamp: Date.now.addingTimeInterval(-daysAgo * 86400), isSimulated: simulated)
}
func status(_ level: ShortageStatus.Level, _ cats: [ManufacturerSupply.Category] = []) -> ShortageStatus {
    ShortageStatus(level: level, manufacturers: cats.enumerated().map { .init(company: "M\($0.offset)", category: $0.element, rawAvailability: nil, updateDate: nil) },
                   initialPostingDate: nil, lastUpdated: nil, fetchedAt: .now)
}
func recall(_ cls: String = "Class II") -> SupplyRiskService.Recall { .init(date: .now, firm: "X", classification: cls) }
let none = status(.none)
let p = pharmacy("P", name: "Main Street Pharmacy"), q = pharmacy("Q", name: "Corner Pharmacy", lat: 39.01), far = pharmacy("FAR", lat: 40)
let tablet = Medication(rxcui: "1", name: "testdrug 10 MG Oral Tablet", displayName: "Testdrug 10 MG Oral Tablet", termType: "SCD")
func est(_ ph: Pharmacy = p, _ s: ShortageStatus = none, _ sig: DrugSignals? = nil, _ med: Medication? = nil, _ r: [AvailabilityReport] = []) -> AvailabilityEstimate {
    AvailabilityEstimator.estimate(for: ph, shortage: s, signals: sig, medication: med, reports: r)
}
func near(_ a: Double, _ b: Double, _ tol: Double = 0.005) -> Bool { abs(a - b) < tol }

// ---------------------------------------------------------------- public-data percentage
section("Public-data percentage (PriorModel)")
check("always shows a percentage, even with zero reports", est().showsPercentage)
check("no shortage, plain pharmacy → 88%", near(est().probability, 0.88), est().percentText)
check("zero reports → Low confidence", est().confidence == .low)
check("resolved shortage → 80%", near(est(p, status(.resolved)).probability, 0.80))
check("FDA unreachable → 75%", near(est(p, .unknown()).probability, 0.75))
let allOut = status(.active, [.unavailable, .unavailable]), allOK = status(.active, [.available, .available]), half = status(.active, [.available, .unavailable])
check("active shortage base: all unavailable 30%, half 52.5%, all available 75%",
      near(PriorModel.baseProbability(allOut), 0.30) && near(PriorModel.baseProbability(half), 0.525) && near(PriorModel.baseProbability(allOK), 0.75))
check("limited counts as half", near(PriorModel.baseProbability(status(.active, [.limited, .limited])), 0.525))
check("shortage with no maker info → 50%", near(PriorModel.baseProbability(status(.active, [.unknown])), 0.50))

var sig = DrugSignals()
sig.yearlyPrescriptions = 1_000_000
let common = est(p, none, sig).probability
sig.yearlyPrescriptions = 20_000; let lessCommon = est(p, none, sig).probability
sig.yearlyPrescriptions = 2_000; let rare = est(p, none, sig).probability
sig.yearlyPrescriptions = 300; let veryRare = est(p, none, sig).probability
check("more commonly prescribed → higher %", common > 0.88 && 0.88 > lessCommon && lessCommon > rare && rare > veryRare, "\(common) \(lessCommon) \(rare) \(veryRare)")
check("very rare drug drops below 60%", veryRare < 0.60, "\(veryRare)")

var s2 = DrugSignals(); s2.deaSchedule = "CII"
check("Schedule II lowers %", est(p, none, s2).probability < 0.88)
s2.deaSchedule = "CIV"; let civ = est(p, none, s2).probability
s2.deaSchedule = "CII"; check("CII lowers more than CIV", est(p, none, s2).probability < civ && civ < 0.88)
s2.deaSchedule = ""; check("not controlled → no change", near(est(p, none, s2).probability, 0.88))

var s3 = DrugSignals(); s3.makers = 1; let oneMaker = est(p, none, s3).probability
s3.makers = 4; let fourMakers = est(p, none, s3).probability
s3.makers = 12; let manyMakers = est(p, none, s3).probability
check("more makers → higher %", oneMaker < fourMakers && fourMakers < manyMakers && near(fourMakers, 0.88))

var s4 = DrugSignals(); s4.recalls = []
check("no recalls → no change", near(est(p, none, s4).probability, 0.88))
s4.recalls = [recall()]; let oneRecall = est(p, none, s4).probability
s4.recalls = [recall(), recall()]; let twoRecalls = est(p, none, s4).probability
s4.recalls = [recall("Class I")]; let classI = est(p, none, s4).probability
check("recalls lower %, more/serious lower more", oneRecall < 0.88 && twoRecalls < oneRecall && near(classI, twoRecalls))

var s5 = DrugSignals(); s5.priceChange = 0.25; let spike = est(p, none, s5).probability
s5.priceChange = 0.12; let rise = est(p, none, s5).probability
s5.priceChange = 0.0; let flat = est(p, none, s5).probability
s5.priceChange = -0.10; let fall = est(p, none, s5).probability
check("price: spike < rise < flat < falling", spike < rise && rise < flat && flat < fall && near(flat, 0.88))

let liquid = Medication(rxcui: "2", name: "x 5 MG/ML Oral Solution", displayName: "x", termType: "SCD")
let inject = Medication(rxcui: "3", name: "x 5 MG/ML Injectable Solution", displayName: "x", termType: "SCD")
check("form: injectable < liquid < tablet", est(p, none, nil, inject).probability < est(p, none, nil, liquid).probability
      && est(p, none, nil, liquid).probability < est(p, none, nil, tablet).probability && near(est(p, none, nil, tablet).probability, 0.88))

check("pharmacy types recognized",
      PharmacyKind.classify("CVS Pharmacy") == .chain && PharmacyKind.classify("Walgreens") == .chain
      && PharmacyKind.classify("Giant Pharmacy") == .grocery && PharmacyKind.classify("Harris Teeter Pharmacy") == .grocery
      && PharmacyKind.classify("Ted Pharmacy") == .independent && PharmacyKind.classify("Peterson Drug") == .independent
      && PharmacyKind.classify("Pharmacy | Kaiser Permanente Ashburn Medical Center") == .institutional
      && PharmacyKind.classify("Inova Loudoun Hospital Pharmacy") == .institutional
      && PharmacyKind.classify("Critter-Rx") == .specialty && PharmacyKind.classify("ABC Compounding Pharmacy") == .specialty
      && PharmacyKind.classify("Pet Meds Vet Pharmacy") == .specialty)
let cvs = pharmacy("C", name: "CVS Pharmacy"), kaiser = pharmacy("K", name: "Kaiser Permanente Pharmacy"), vet = pharmacy("V", name: "Critter-Rx Veterinary Pharmacy")
check("no shortage: chain slightly above independent", est(cvs).probability > est(p).probability)
check("during shortage: independent slightly above chain", est(p, half).probability > est(cvs, half).probability)
check("hospital/Kaiser pharmacy lower", est(kaiser).probability < est(p).probability)
sig.yearlyPrescriptions = 2_000_000
check("specialty/vet pharmacy capped at 15% even for a common drug", est(vet, none, sig).probability <= 0.15 + 1e-9, "\(est(vet, none, sig).probability)")

var worst = DrugSignals(); worst.yearlyPrescriptions = 100; worst.deaSchedule = "CII"; worst.makers = 1; worst.recalls = [recall(), recall()]; worst.priceChange = 0.5
var best = DrugSignals(); best.yearlyPrescriptions = 5_000_000; best.deaSchedule = ""; best.makers = 30; best.recalls = []; best.priceChange = -0.3
let lo = est(vet, allOut, worst, inject).probability, hi = est(cvs, none, best, tablet).probability
check("percentage always between 3% and 97%", lo >= 0.03 && hi <= 0.97, "\(lo) \(hi)")
check("factors are listed for the user", est(p, half, best, tablet).factors.count >= 5)
check("public-data % reported separately", near(est(p, none, nil, nil, [report(p, false, daysAgo: 0.1)]).publicDataProbability, 0.88))

// ---------------------------------------------------------------- crowd reports
section("Crowd reports")
var e = est(p, none, nil, nil, [report(p, false, daysAgo: 0.01)])
check("1 fresh 'no' lowers %, confidence Moderate", e.probability < 0.88 && e.confidence == .moderate, e.percentText)
e = est(p, none, nil, nil, [0.2, 0.5, 1.0, 1.5, 2.0, 2.5].map { report(p, false, daysAgo: $0) })
check("6 recent 'no' → Unlikely, High confidence", e.tier == .unlikely && e.confidence == .high, e.percentText)
e = est(p, allOut, nil, nil, [0.2, 0.6, 1.0, 1.4].map { report(p, true, daysAgo: $0) })
check("recent 'yes' reports can overcome a bad shortage", e.probability > 0.6, e.percentText)
check("reports older than 30 days ignored", near(est(p, none, nil, nil, (0..<5).map { report(p, false, daysAgo: 40 + Double($0)) }).probability, 0.88))
check("future-dated report ignored", near(est(p, none, nil, nil, [report(p, false, daysAgo: -2)]).probability, 0.88))
e = est(p, half, nil, nil, [report(p, false, daysAgo: 20), report(p, true, daysAgo: 0.1), report(p, true, daysAgo: 1.2)])
check("recent yes outweighs old no", e.probability > est(p, half).probability)
let nearNo = (0..<6).map { report(q, false, daysAgo: 0.3 + Double($0)) }
check("nearby pharmacies' reports nudge the estimate", est(p, none, nil, nil, nearNo).probability < 0.88)
check("reports >5 miles away ignored", near(est(p, none, nil, nil, (0..<6).map { report(far, false, daysAgo: 0.3 + Double($0)) }).probability, 0.88))
let moved = pharmacy("P-new-id", name: "Main Street Pharmacy", lat: 39.0003)
check("report matched by location when the map ID changes", est(moved, none, nil, nil, [report(p, false, daysAgo: 0.1)]).probability < 0.88)
let one = est(p, none, nil, nil, [report(p, false, daysAgo: 0.1)]).probability
let spam = est(p, none, nil, nil, (0..<10).map { report(p, false, daysAgo: 0.1 + Double($0) * 0.0003) }).probability
check("burst of 10 spam reports counts as 1", near(one, spam, 0.01), "\(one) vs \(spam)")
check("reports hours apart count separately", est(p, none, nil, nil, (0..<3).map { report(p, false, daysAgo: Double($0) * 0.2) }).probability < one)
check("simulated flag carried through", est(p, none, nil, nil, [report(p, true, daysAgo: 1, simulated: true)]).usesSimulatedData)
var ok = true
for n in 0..<60 { let x = est(p, half, worst, inject, (0..<n).map { report(p, $0 % 3 == 0, daysAgo: Double($0) * 0.3) }).probability; if !(0...1).contains(x) || x.isNaN { ok = false } }
check("never NaN or outside 0–100%", ok)

// ---------------------------------------------------------------- trends
section("Local trends")
func weeks(_ yes: (Int) -> Int) -> [AvailabilityReport] {
    var out: [AvailabilityReport] = []
    for w in 0..<5 { for i in 0..<6 { out.append(report(p, i < yes(w), daysAgo: Double(w) * 7 + 1 + Double(i) * 0.5)) } }
    return out
}
check("no data → not enough data, no warning", TrendAnalyzer.analyze(reports: [], pharmacies: [p]).direction == .notEnoughData
      && TrendAnalyzer.analyze(reports: [], pharmacies: [p]).earlyWarning == nil)
check("declining detected", TrendAnalyzer.analyze(reports: weeks { $0 + 1 }, pharmacies: [p]).direction == .declining)
check("improving detected", TrendAnalyzer.analyze(reports: weeks { 6 - $0 }, pharmacies: [p]).direction == .improving)
check("stable detected", TrendAnalyzer.analyze(reports: weeks { _ in 3 }, pharmacies: [p]).direction == .stable)
check("other areas' reports excluded", TrendAnalyzer.analyze(reports: weeks { $0 + 1 }, pharmacies: [pharmacy("X", lat: 45)]).points.isEmpty)
let trio = ["A", "B", "C"].enumerated().map { pharmacy($0.element, lat: 39 + Double($0.offset) * 0.01) }
let multi = trio.flatMap { [report($0, true, daysAgo: 10), report($0, true, daysAgo: 12), report($0, false, daysAgo: 1)] }
check("3 declining pharmacies → early warning", TrendAnalyzer.analyze(reports: multi, pharmacies: trio).earlyWarning != nil)

// ---------------------------------------------------------------- supply risk
section("Supply risk score")
typealias S = SupplyRiskService
func risk(_ s: ShortageStatus, makers: Int, recalls: Int, price: Double?) -> SupplyRisk {
    var f = [S.shortageFactor(s)!, S.makersFactor(makers), S.recallFactor((0..<recalls).map { _ in recall() })]
    if let price { f.append(S.priceFactor(price)) }
    return SupplyRisk(factors: f, checkedAt: .now, officialShortage: s.level == .active, unavailableSources: [])
}
check("healthy generic → Low", risk(none, makers: 10, recalls: 0, price: -0.05).level == .low)
check("official shortage always ≥ Elevated", risk(allOK, makers: 20, recalls: 0, price: -0.2).level == .elevated)
check("everything bad → High", risk(allOut, makers: 1, recalls: 3, price: 0.3).level == .high)
check("missing price data still scores", risk(none, makers: 5, recalls: 0, price: nil).factors.count == 3)
check("3-month price change math", near(S.threeMonthChange(["2026-06-01": [1.0], "2026-09-20": [1.2, 1.2]]) ?? 0, 0.2, 0.0001))
check("needs a baseline ~3 months back", S.threeMonthChange(["2026-09-01": [1.0], "2026-09-20": [1.1]]) == nil)

// ---------------------------------------------------------------- matching & text
section("FDA matching and names")
check("5 mg does not match 15 mg", !FDAShortageService.containsWord("5 mg", in: "tablet, 15 mg"))
check("5 mg matches '5 mg; 5 mg'", FDAShortageService.containsWord("5 mg", in: "tablet, 5 mg; 5 mg"))
check("methylphenidate ≠ dexmethylphenidate", !FDAShortageService.containsWord("methylphenidate", in: "dexmethylphenidate tablet"))
check("strength parsed", FDAShortageService.strength(in: "amphetamine aspartate 7.5 MG / x") == "7.5 mg")
check("availability categories", FDAShortageService.category("Limited Supply Available. Next Delivery") == .limited
      && FDAShortageService.category("unavailable") == .unavailable && FDAShortageService.category("Available") == .available && FDAShortageService.category(nil) == .unknown)
let details = MedicationDetails(medication: tablet, ingredients: ["amphetamine"], relatedRxcuis: ["1"], genericName: "amphetamine sulfate 10 MG Oral Tablet")
func rec(_ form: String, _ pres: String, _ gen: String = "Amphetamine Sulfate Tablet") -> ShortageRecord {
    ShortageRecord(package_ndc: "1", generic_name: gen, company_name: "A", availability: "Available", status: "Current", dosage_form: form, presentation: pres, update_date: nil, initial_posting_date: nil)
}
check("matches same strength + form", FDAShortageService.matches(rec("Tablet", "Tablet, 10 mg"), details))
check("rejects other strength", !FDAShortageService.matches(rec("Tablet", "Tablet, 20 mg"), details))
check("rejects extended release for a regular tablet", !FDAShortageService.matches(rec("Tablet, Extended Release", "Tablet, Extended Release, 10 mg"), details))
check("rejects other ingredient", !FDAShortageService.matches(rec("Tablet", "Tablet, 10 mg", "Lisinopril Tablet"), details))
check("short names", Medication(rxcui: "1", name: "x", displayName: "8 HR Metadate 20 MG Extended Release Oral Tablet", termType: "SBD").shortName == "Metadate 20 mg ER tablet"
      && Medication(rxcui: "1", name: "x", displayName: "amoxicillin (as amoxicillin trihydrate) 500 MG Oral Capsule", termType: "SCD").shortName == "amoxicillin 500 mg capsule")

// ---------------------------------------------------------------- community + misc
section("Community reports and other")
check("server date with 6 decimals parses", CommunityReportService.parseDate("2026-09-24T01:02:03.123456+00:00") != nil
      && CommunityReportService.parseDate("2026-09-24T01:02:03+00:00") != nil)
check("ISO string safe for URLs", !CommunityReportService.isoString(.now).contains("+"))
let gp = try GooglePlacesService.parse(#"{"places":[{"displayName":{"text":"CVS Pharmacy"},"location":{"latitude":39,"longitude":-77.5},"rating":3.4,"userRatingCount":212,"currentOpeningHours":{"openNow":true,"nextCloseTime":"2026-09-24T01:00:00Z"}}]}"#.data(using: .utf8)!)
check("Google response parses (feature is off, code kept)", gp.first?.rating == 3.4 && gp.first?.isOpenNow == true)
check("Google feature is OFF for release", FeatureFlags.googleRatingsAndHours == false)

let store = await ReportStore(service: nil)   // nil = never touches the real database
await store.clearAll()
let m1 = Medication(rxcui: "t1", name: "x", displayName: "Test 10 MG", termType: "SCD"), m2 = Medication(rxcui: "t2", name: "y", displayName: "Other", termType: "SCD")
await store.add(.inStock, medication: m1, pharmacy: cvs)
await store.add(.outOfStock, medication: m1, pharmacy: cvs)   // blocked by cooldown
await store.add(.inStock, medication: m1, pharmacy: kaiser)
await store.add(.inStock, medication: m2, pharmacy: cvs)
let count = await store.myReports.count
check("one report per pharmacy+medication per hour", count == 3, "\(count)")
await store.clearAll()
check("demo data is repeatable and labeled", {
    let a = DemoDataGenerator.reports(medication: m1, pharmacy: q, nationalScore: 0.6), b = DemoDataGenerator.reports(medication: m1, pharmacy: q, nationalScore: 0.6)
    return a.count == b.count && a.allSatisfy(\.isSimulated)
}())

print("\n\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
