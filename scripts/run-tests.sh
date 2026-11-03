#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

derived_data="$HOME/Library/Caches/Nubrix/DerivedData-tests"
if [[ $# -gt 0 && "$1" != -* ]]; then
  derived_data="$1"
  shift
fi

mkdir -p "$derived_data"
log="$(mktemp -t nubrix-tests)"
trap 'rm -f "$log"' EXIT

status=0
/usr/bin/xcodebuild test \
  -project Nubrix.xcodeproj \
  -scheme NubrixTests \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  -onlyUsePackageVersionsFromResolvedFile \
  ONLY_ACTIVE_ARCH=YES \
  "$@" 2>&1 | tee "$log" || status=${PIPESTATUS[0]}

echo
echo "---- Nubrix test summary ----"
grep -E "^Test Suite 'All tests' (passed|failed)|^[[:space:]]*Executed [0-9]+ tests?|\*\* TEST (SUCCEEDED|FAILED) \*\*|: error: |^Test Case .* failed" "$log" | tail -n 40 || true

if [[ $status -eq 0 ]]; then
  echo "PASS"
else
  echo "FAIL (xcodebuild exit $status, derived data: $derived_data)"
fi
exit "$status"
