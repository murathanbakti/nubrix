#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
repo_url="https://github.com/murathanbakti/nubrix"
feed_url="$repo_url/releases/latest/download/appcast.xml"

usage() {
  cat >&2 <<'EOF2'
usage: scripts/make-appcast.sh --tools DIR --tag vX.Y.Z --zip dist/Nubrix-X.Y.Z.zip --out dist/appcast.xml

The signing key comes from SPARKLE_ED_KEY_FILE (path to the exported private
key), else SPARKLE_ED_PRIVATE_KEY (the key itself, passed on stdin), else the
login keychain account nubrix.
EOF2
  exit 2
}
fail() { echo "make-appcast: $*" >&2; exit 1; }

tools="" tag="" zip="" out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tools | --tag | --zip | --out)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in
        --tools) tools="$2" ;;
        --tag) tag="$2" ;;
        --zip) zip="$2" ;;
        --out) out="$2" ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$tools" ] && [ -n "$tag" ] && [ -n "$zip" ] && [ -n "$out" ] || usage
[[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || fail "tag must be vX.Y.Z"
version="${BASH_REMATCH[1]}"
[ -f "$zip" ] && [ "$(basename "$zip")" = "Nubrix-$version.zip" ] || fail "expected $zip to be Nubrix-$version.zip"
for t in generate_appcast sign_update; do [ -x "$tools/$t" ] || fail "missing $tools/$t"; done

key_args=()
key_stdin=0
if [ -n "${SPARKLE_ED_KEY_FILE:-}" ]; then
  [ -f "$SPARKLE_ED_KEY_FILE" ] && [ -s "$SPARKLE_ED_KEY_FILE" ] || fail "SPARKLE_ED_KEY_FILE is missing or empty"
  key_args=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
elif [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
  key_args=(--ed-key-file -)
  key_stdin=1
else
  key_args=(--account nubrix)
fi

with_key() {
  if [ "$key_stdin" = 1 ]; then
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$@" "${key_args[@]}"
  else
    "$@" "${key_args[@]}"
  fi
}

repo_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$root/Nubrix/Info.plist" 2>/dev/null || true)"
[[ "$repo_key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "Nubrix/Info.plist has no valid SUPublicEDKey; run scripts/setup-sparkle-key.sh and commit the result"

work="$(mktemp -d "${TMPDIR:-/tmp}/nubrix-appcast.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/archives" "$work/app"
cp "$zip" "$work/archives/"
ditto -x -k "$zip" "$work/app"
[ "$(ls "$work/app")" = "Nubrix.app" ] || fail "the zip must hold only Nubrix.app"
plist="$work/app/Nubrix.app/Contents/Info.plist"
pl() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
[ "$(pl CFBundleShortVersionString)" = "$version" ] || fail "CFBundleShortVersionString is not $version"
build="$(pl CFBundleVersion)"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || fail "CFBundleVersion '$build' must be a positive integer"
[ "$(pl LSMinimumSystemVersion)" = "14.0" ] || fail "LSMinimumSystemVersion is not 14.0"
[ "$(pl SUFeedURL)" = "$feed_url" ] || fail "SUFeedURL is not $feed_url"
[ "$(pl SUPublicEDKey)" = "$repo_key" ] || fail "the app's SUPublicEDKey differs from Nubrix/Info.plist"

code="$(curl -sS --proto '=https' --tlsv1.2 -L --max-redirs 5 -o "$work/previous.xml" -w '%{http_code}' "$feed_url" || true)"
case "$code" in
  200)
    prev="$(xmllint --xpath 'string(//*[local-name()="item"][1]/*[local-name()="version"])' "$work/previous.xml")"
    [[ "$prev" =~ ^[0-9]+$ ]] || fail "cannot read sparkle:version from the published appcast"
    [ "$build" -gt "$prev" ] || fail "CFBundleVersion $build is not greater than the published $prev; bump CURRENT_PROJECT_VERSION"
    ;;
  404) echo "No published appcast yet; writing the first one." ;;
  *) fail "unexpected HTTP $code for $feed_url" ;;
esac

(cd "$work" && with_key "$tools/generate_appcast" \
  --download-url-prefix "$repo_url/releases/download/$tag/" \
  --link "$repo_url/releases/tag/$tag" \
  --maximum-deltas 0 --maximum-versions 1 \
  -o "$work/appcast.xml" "$work/archives")

feed="$work/appcast.xml"
x() { xmllint --xpath "$1" "$feed"; }
item='//*[local-name()="item"]'
[ "$(x "count($item)")" = 1 ] || fail "expected exactly one item"
[ "$(x "string($item/*[local-name()=\"version\"])")" = "$build" ] || fail "sparkle:version is not $build"
[ "$(x "string($item/*[local-name()=\"shortVersionString\"])")" = "$version" ] || fail "shortVersionString is not $version"
[ "$(x "string($item/*[local-name()=\"minimumSystemVersion\"])")" = "14.0" ] || fail "minimumSystemVersion is not 14.0"
[ "$(x "string($item/*[local-name()=\"enclosure\"]/@url)")" = "$repo_url/releases/download/$tag/Nubrix-$version.zip" ] || fail "enclosure URL is wrong"
[ "$(x "string($item/*[local-name()=\"enclosure\"]/@length)")" = "$(stat -f %z "$zip")" ] || fail "enclosure length is wrong"
sig="$(x "string($item/*[local-name()=\"enclosure\"]/@*[local-name()=\"edSignature\"])")"
[ -n "$sig" ] || fail "no EdDSA signature: the private key does not match SUPublicEDKey"
[ "$(x "count($item/*[local-name()=\"deltas\" or local-name()=\"releaseNotesLink\" or local-name()=\"description\"])")" = 0 ] || fail "unexpected deltas or release notes"
grep -q '<!-- sparkle-signatures:' "$feed" && tail -n 4 "$feed" | grep -q '^edSignature: ' || fail "the appcast is not signed"
with_key "$tools/sign_update" --verify "$feed" > /dev/null || fail "appcast signature does not verify"
with_key "$tools/sign_update" --verify "$zip" "$sig" > /dev/null || fail "archive signature does not verify"
cp "$feed" "$out"
echo "Appcast: $out (sparkle:version $build, $version)"
