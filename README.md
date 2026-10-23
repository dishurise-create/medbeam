# MedBeam

**Find your medication before you drive.** MedBeam is a free iPhone app that shows which nearby pharmacies are most likely to have a prescription in stock, and warns when a medication is getting harder to find.

Built for the 2026 Congressional App Challenge (Virginia's 10th District).

- Privacy policy: https://dishurise-create.github.io/medbeam/privacy.html
- Support: https://dishurise-create.github.io/medbeam/support.html

## The problem

During drug shortages (ADHD medications, children's antibiotics, GLP-1 drugs), patients often call pharmacy after pharmacy. The FDA publishes *national* shortage data, but nothing tells a patient what is likely at the pharmacies near them. No public system shares live pharmacy inventory.

## What the app does

- **Search any prescription** (exact drug, strength and form) and a ZIP code.
- **Map of nearby pharmacies**, ranked by an estimated chance of having it in stock.
- **"See why"** breakdown for every percentage, with the data source for each factor.
- **Supply risk score** (0 to 100) for the medication nationally.
- **Shortage Watch** for saved medications.
- **Anonymous community reports** ("they had it" / "they didn't") that improve estimates for everyone nearby.
- **Early warning** when several nearby pharmacies report declining availability. This is always labeled separately from official FDA shortages.

## How the percentage is calculated

MedBeam never claims to know a pharmacy's real inventory. Every number is an estimate.

1. **Starting point from the FDA Drug Shortages database** for the exact product:
   no shortage 88%, resolved 80%, being discontinued 60%, active shortage 30 to 75% depending on how many makers report it available.
2. **Adjusted with public data** on the log-odds scale, so effects add up and the result stays between 3% and 97%:
   how commonly it is prescribed (Medicaid utilization), controlled-substance schedule (FDA NDC Directory), number of approved makers, recalls in the last 6 months (FDA Enforcement Reports), 3-month wholesale price trend (Medicaid NADAC), dosage form, and pharmacy type.
3. **Updated by community reports** with a Bayesian prior-plus-evidence model. Recent reports count more (a report's weight halves every 4 days), reports from pharmacies within 5 miles count a little, and a burst of repeated reports counts as one (spam protection).

The label next to each percentage says how much local evidence is behind it: "Public data only", "Some local reports", or "Many local reports".

The adjustment sizes are informed judgments, not measured probabilities. They are kept in one file (`MedBeam/Engine/PriorModel.swift`) so they can be tuned as real reports arrive.

## Data sources

| Source | Used for |
|---|---|
| FDA Drug Shortages (openFDA) | Official shortage status and manufacturer availability |
| FDA NDC Directory (openFDA) | Number of makers, controlled-substance schedule |
| FDA Enforcement Reports (openFDA) | Recent recalls |
| Medicaid NADAC | Wholesale price trend |
| Medicaid State Drug Utilization | How commonly a medication is prescribed |
| RxNorm (National Library of Medicine) | Standard medication names, strengths and forms |
| Apple MapKit | Pharmacy locations |
| Supabase (PostgreSQL) | Anonymous community reports |

## Privacy

No account. The app never asks for a name, prescription, doctor, diagnosis or insurance, and uses the ZIP code typed in rather than GPS. A shared report contains only a medication code, the pharmacy's map location, the answer and the time. Database rules (`backend/supabase-setup.sql`) let the app only read recent reports and add new ones, with rate limits.

## Project layout

```
MedBeam/                 SwiftUI app (iOS 18+)
  Engine/                Estimate math: PriorModel, AvailabilityEstimator, TrendAnalyzer
  Services/              FDA, RxNorm, Medicaid, MapKit, community reports
  Views/                 Screens
backend/                 Database setup script and guide
tests/                   Automated tests (offline logic + live data checks)
design/                  App icon and App Store artwork generators
docs/                    Privacy policy, support page, App Store listing text
```

## Build and test

1. Open `MedBeam.xcodeproj` in Xcode and press Run.
2. Run the tests: `./tests/run.sh` (71 logic tests) or `./tests/run.sh live` (also checks real FDA, Medicaid, RxNorm and Apple Maps data across 9 ZIP codes).

## Use of AI

<!-- Review and edit this section so it accurately describes your own work before submitting. -->
I used Claude (Anthropic), an AI coding assistant, while building MedBeam. I chose the problem, decided on the features and design, and tested and reviewed the app. Claude helped write and debug much of the Swift code, research the public data sources, and draft the App Store text. I reviewed the code and can explain how each part works, including the percentage model above.

## Medical disclaimer

MedBeam is an information tool, not medical advice. Estimates may be wrong; always call the pharmacy to confirm. Never change a medication or dose without talking to a doctor or pharmacist.
