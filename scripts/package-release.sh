#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
derived="${NUBRIX_DERIVED_DATA:-$HOME/Library/Caches/Nubrix/DD-release}"
dist="$root/dist"
log="$(dirname "$derived")/package-release.log"

usage() {
  cat >&2 <<'EOF'
usage:
  scripts/package-release.sh [VERSION]
      Builds, signs (when NUBRIX_SIGN_IDENTITY is set), notarizes (when
      NOTARY_KEY_PATH is set) and zips the app into dist/.
  scripts/package-release.sh --build-only [VERSION]
      Builds and checks the app, then writes dist/Nubrix-<version>-unsigned.zip
      and dist/dSYMs-<version>.zip. No signing secrets are needed or read.
  scripts/package-release.sh --app PATH [VERSION]
      Signs, notarizes and zips an app made by --build-only, without building.
EOF
  exit 2
}

fail() {
  echo "package-release: $*" >&2
  exit 1
}

mode=all
app=""
while [ $# -gt 0 ]; do
  case "$1" in
    --build-only) mode=build; shift ;;
    --app) [ $# -ge 2 ] || usage; mode=sign; app="${2%/}"; shift 2 ;;
    -*) usage ;;
    *) break ;;
  esac
done
[ $# -le 1 ] || usage

if [ "$mode" = build ] && [ -n "${NUBRIX_SIGN_IDENTITY:-}${NOTARY_KEY_PATH:-}" ]; then
  fail "--build-only does not sign; unset NUBRIX_SIGN_IDENTITY and NOTARY_KEY_PATH"
fi
if [ -n "${NUBRIX_SIGN_IDENTITY:-}" ] && [ "$NUBRIX_SIGN_IDENTITY" != "-" ]; then
  export NUBRIX_REQUIRE_SPARKLE_KEY=1
fi
if [ -n "${NOTARY_KEY_PATH:-}" ] && [ -z "${NUBRIX_SIGN_IDENTITY:-}" ]; then
  fail "NOTARY_KEY_PATH is set but NUBRIX_SIGN_IDENTITY is not; only Developer ID builds can be notarized"
fi

if [ $# -ge 1 ]; then
  version="$1"
elif [ "$mode" = sign ]; then
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || true)"
  [ -n "$version" ] || fail "could not read the version of $app"
else
  settings="$(xcodebuild -project "$root/Nubrix.xcodeproj" -scheme Nubrix -configuration Release -showBuildSettings 2>/dev/null || true)"
  version="$(awk '$1 == "MARKETING_VERSION" { print $3; exit }' <<< "$settings")"
  [ -n "$version" ] || fail "could not read MARKETING_VERSION"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "invalid version '$version', expected X.Y.Z"

build() {
  mkdir -p "$(dirname "$log")"
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
  "$root/scripts/strip-sparkle-downloader.sh" "$app"
}

check_app() {
  [ -d "$app/Contents" ] || fail "not an app bundle: $app"
  local built
  built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
  [ "$built" = "$version" ] || fail "requested version $version but the app is $built"

  "$root/scripts/verify-bundle.sh" "$app"

  local bin archs arch
  while IFS= read -r -d '' bin; do
    case "$(file -b "$bin")" in Mach-O*) ;; *) continue ;; esac
    archs="$(lipo -archs "$bin")"
    for arch in arm64 x86_64; do
      case " $archs " in
        *" $arch "*) ;;
        *) fail "${bin#"$app"/} lacks $arch (has: $archs)" ;;
      esac
    done
  done < <(find "$app" -type f -print0)
}

zip_dsyms() {
  (cd "$derived/Build/Products/Release" && zip -qry "$dist/dSYMs-$version.zip" ./*.dSYM)
}

if [ "$mode" = build ]; then
  build
  check_app
  rm -rf "$dist"
  mkdir -p "$dist"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$dist/Nubrix-$version-unsigned.zip"
  zip_dsyms
  echo
  echo "Version  $version"
  echo "Archs    arm64 x86_64"
  echo "App      $dist/Nubrix-$version-unsigned.zip"
  echo "dSYMs    $dist/dSYMs-$version.zip"
  exit 0
fi

if [ "$mode" = all ]; then
  build
  check_app
  rm -rf "$dist"
  mkdir -p "$dist"
else
  check_app
  mkdir -p "$dist"
  rm -f "$dist/Nubrix-$version.zip" "$dist/Nubrix-$version.zip.sha256" "$dist/nubrix.rb" "$dist/notary-log.json" "$dist/appcast.xml"
fi

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
if [ "$mode" = all ]; then
  zip_dsyms
fi
sha="$(shasum -a 256 "$dist/$zip" | awk '{ print $1 }')"
printf '%s  %s\n' "$sha" "$zip" > "$dist/$zip.sha256"
"$root/scripts/render-cask.sh" "$version" "$sha" > "$dist/nubrix.rb"

echo
echo "Version  $version"
echo "Archs    arm64 x86_64"
echo "Signing  $signing"
echo "Zip      $dist/$zip"
if [ "$mode" = all ]; then
  echo "dSYMs    $dist/dSYMs-$version.zip"
fi
echo "SHA-256  $sha"
echo "Cask     $dist/nubrix.rb"
