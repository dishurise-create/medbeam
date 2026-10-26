#!/bin/zsh
# Runs MedBeam's tests. Usage:  ./tests/run.sh         (offline logic tests)
#                               ./tests/run.sh live    (also checks the real FDA / Medicaid / Apple Maps data)
set -e
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
SRC=(MedBeam/Engine/*.swift MedBeam/Models/*.swift MedBeam/Config/*.swift
     MedBeam/Services/FDAShortageService.swift MedBeam/Services/SupplyRiskService.swift MedBeam/Services/RxNormService.swift
     MedBeam/Services/CommunityReportService.swift MedBeam/Services/ReportStore.swift
     MedBeam/Services/PharmacySearchService.swift)
echo "== Offline tests =="
swiftc -o "$OUT/offline" tests/offline/main.swift $SRC 2>&1 | grep -E "error" || true
"$OUT/offline"
if [[ "$1" == "live" ]]; then
  echo "\n== Live data tests (needs internet, ~2 minutes) =="
  swiftc -o "$OUT/live" tests/live/main.swift $SRC 2>&1 | grep -E "error" || true
  "$OUT/live"
fi
rm -f "$HOME/Library/Application Support/reports.json"
