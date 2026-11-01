#!/bin/bash
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <path-to-Nubrix.app>" >&2; exit 2; }
app="${1%/}"
key="${NOTARY_KEY_PATH:?set NOTARY_KEY_PATH to the App Store Connect API key (.p8)}"
key_id="${NOTARY_KEY_ID:?set NOTARY_KEY_ID}"
issuer="${NOTARY_ISSUER_ID:?set NOTARY_ISSUER_ID}"
log_dir="${NUBRIX_NOTARY_LOG_DIR:-$(dirname "$app")}"

fail() {
  echo "notarize-release: $*" >&2
  exit 1
}

[ -d "$app/Contents" ] || fail "not an app bundle: $app"
[ -f "$key" ] || fail "API key file not found: $key"

work="$(mktemp -d "${TMPDIR:-/tmp}/nubrix-notary.XXXXXX")"
trap 'rm -rf "$work"' EXIT

auth=(--key "$key" --key-id "$key_id" --issuer "$issuer")
upload="$work/$(basename "$app" .app)-notary.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$upload"

echo "Submitting $(basename "$app") to the Apple notary service…"
rc=0
xcrun notarytool submit "$upload" "${auth[@]}" --wait --timeout 45m --output-format json > "$work/submit.json" || rc=$?

id="$(plutil -extract id raw -o - "$work/submit.json" 2>/dev/null || true)"
status="$(plutil -extract status raw -o - "$work/submit.json" 2>/dev/null || true)"
if [ -z "$id" ]; then
  cat "$work/submit.json" >&2 2>/dev/null || true
  fail "notarytool submit failed (exit $rc) without a submission id"
fi
echo "Submission $id: $status"

mkdir -p "$log_dir"
xcrun notarytool log "$id" "${auth[@]}" "$log_dir/notary-log.json" >/dev/null 2>&1 || true

if [ "$status" != "Accepted" ]; then
  [ -f "$log_dir/notary-log.json" ] && cat "$log_dir/notary-log.json" >&2
  fail "notarization status is '$status'"
fi

xcrun stapler staple "$app" || fail "stapler staple failed"
xcrun stapler validate "$app" >/dev/null || fail "stapler validate failed"

assessment="$(spctl --assess --type execute --verbose=2 "$app" 2>&1)" || { echo "$assessment" >&2; fail "Gatekeeper rejects the stapled app"; }
grep -q 'source=Notarized Developer ID' <<< "$assessment" || { echo "$assessment" >&2; fail "Gatekeeper does not report a notarized Developer ID app"; }

echo "Notarized and stapled: $app"
