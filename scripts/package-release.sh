#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
derived="${NUBRIX_DERIVED_DATA:-$HOME/Library/Caches/Nubrix/DD-release}"
dist="$root/dist"
log="$(dirname "$derived")/package-release.log"

fail() {
  echo "package-release: $*" >&2
  exit 1
}

mkdir -p "$(dirname "$log")"

if [ -n "${NOTARY_KEY_PATH:-}" ] && [ -z "${NUBRIX_SIGN_IDENTITY:-}" ]; then
  fail "NOTARY_KEY_PATH is set but NUBRIX_SIGN_IDENTITY is not; only Developer ID builds can be notarized"
fi

if [ $# -ge 1 ]; then
  version="$1"
else
  version="$(xcodebuild -project "$root/Nubrix.xcodeproj" -scheme Nubrix -configuration Release -showBuildSettings 2>/dev/null \
    | awk '$1 == "MARKETING_VERSION" { print $3; exit }')"
  [ -n "$version" ] || fail "could not read MARKETING_VERSION"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid version '$version', expected X.Y.Z"

rm -rf "$derived/Build/Products/Release"

echo "Building Nubrix $version (Release, arm64 + x86_64)…"
if ! xcodebuild -quiet \
  -project "$root/Nubrix.xcodeproj" \
  -scheme Nubrix \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$derived" \
  -onlyUsePackageVersionsFromResolvedFile \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  build > "$log" 2>&1; then
  grep -E "error:|BUILD FAILED" "$log" | head -20 >&2
  fail "build failed, full log: $log"
fi

app="$derived/Build/Products/Release/Nubrix.app"
[ -d "$app" ] || fail "build output not found: $app"

built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[ "$built" = "$version" ] || fail "requested version $version but the app is $built"

"$root/scripts/verify-bundle.sh" "$app"

binaries=(
  "$app/Contents/MacOS/Nubrix"
  "$app/Contents/XPCServices/NubrixHelper.xpc/Contents/MacOS/NubrixHelper"
)
for fw in "$app"/Contents/Frameworks/*.framework; do
  binaries+=("$fw/Versions/A/$(basename "$fw" .framework)")
done
for bin in "${binaries[@]}"; do
  [ -f "$bin" ] || fail "missing binary $bin"
  archs="$(lipo -archs "$bin")"
  for arch in arm64 x86_64; do
    case " $archs " in
      *" $arch "*) ;;
      *) fail "$(basename "$bin") lacks $arch (has: $archs)" ;;
    esac
  done
done

rm -rf "$dist"
mkdir -p "$dist"

signing="ad-hoc, not notarized"
if [ -n "${NUBRIX_SIGN_IDENTITY:-}" ]; then
  "$root/scripts/sign-release.sh" "$app"
  "$root/scripts/verify-bundle.sh" "$app"
  signing="Developer ID (${NUBRIX_TEAM_ID:-?}), not notarized"
  if [ -n "${NOTARY_KEY_PATH:-}" ]; then
    NUBRIX_NOTARY_LOG_DIR="$dist" "$root/scripts/notarize-release.sh" "$app"
    signing="Developer ID (${NUBRIX_TEAM_ID:-?}), notarized and stapled"
  fi
fi

zip="Nubrix-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$dist/$zip"
dsyms="dSYMs-$version.zip"
(cd "$derived/Build/Products/Release" && zip -qry "$dist/$dsyms" ./*.dSYM)
sha="$(shasum -a 256 "$dist/$zip" | awk '{ print $1 }')"
printf '%s  %s\n' "$sha" "$zip" > "$dist/$zip.sha256"
"$root/scripts/render-cask.sh" "$version" "$sha" > "$dist/nubrix.rb"

echo
echo "Version  $version"
echo "Archs    arm64 x86_64"
echo "Signing  $signing"
echo "Zip      $dist/$zip"
echo "dSYMs    $dist/$dsyms"
echo "SHA-256  $sha"
echo "Cask     $dist/nubrix.rb"
