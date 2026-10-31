#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
derived="${NUBRIX_DERIVED_DATA:-$HOME/Library/Caches/Nubrix/DerivedData}"
dest="${NUBRIX_INSTALL_DIR:-/Applications}"
open_after=0
[ "${1:-}" = "--open" ] && open_after=1

expected_xpc="NubrixHelper.xpc"
expected_frameworks="Lottie.framework MediaRemoteAdapter.framework Sparkle.framework"

fail() {
  echo "Bundle check failed: $*" >&2
  exit 1
}

verify_bundle() {
  local b="$1" entitlements xpc frameworks stale
  [ -d "$b" ] || fail "missing $b"

  xpc="$(ls -1 "$b/Contents/XPCServices" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
  [ "$xpc" = "$expected_xpc" ] || fail "XPCServices is '$xpc', expected '$expected_xpc'"

  frameworks="$(ls -1 "$b/Contents/Frameworks" 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
  [ "$frameworks" = "$expected_frameworks" ] || fail "Frameworks is '$frameworks', expected '$expected_frameworks'"

  stale="$(find "$b" -iname '*boring*' | head -5)"
  [ -z "$stale" ] || fail "stale upstream files: $stale"

  codesign --verify --strict --deep "$b" >/dev/null 2>&1 || fail "codesign verification failed"
  local details
  details="$(codesign -dv "$b" 2>&1)"
  grep -q 'flags=.*runtime' <<< "$details" || fail "hardened runtime is off"

  entitlements="$(codesign -d --entitlements :- "$b" 2>/dev/null)"
  ! grep -q 'com.apple.security.get-task-allow' <<< "$entitlements" || fail "get-task-allow is present"
  grep -q 'com.apple.security.cs.disable-library-validation' <<< "$entitlements" || fail "disable-library-validation is missing"

  entitlements="$(codesign -d --entitlements :- "$b/Contents/XPCServices/$expected_xpc" 2>/dev/null)"
  ! grep -q 'com.apple.security.get-task-allow' <<< "$entitlements" || fail "get-task-allow is present in the helper"
}

log="$(dirname "$derived")/build.log"
mkdir -p "$(dirname "$log")"
rm -rf "$derived/Build/Products/Release"

echo "Building Nubrix (Release)…"
if ! xcodebuild -quiet \
  -project "$root/Nubrix.xcodeproj" \
  -scheme Nubrix \
  -configuration Release \
  -derivedDataPath "$derived" \
  -destination "platform=macOS,arch=$(uname -m)" \
  build > "$log" 2>&1; then
  grep -E "error:|BUILD FAILED" "$log" | head -20 >&2
  echo "Build failed. Full log: $log" >&2
  exit 1
fi

app="$derived/Build/Products/Release/Nubrix.app"
if [ ! -d "$app" ]; then
  echo "Build output not found: $app" >&2
  exit 1
fi

verify_bundle "$app"

if pgrep -xq Nubrix; then
  echo "Quitting the running Nubrix…"
  pkill -TERM -x Nubrix || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq Nubrix || break; sleep 0.5; done
  pkill -KILL -x Nubrix || true
fi

rm -rf "$dest/Nubrix.app"
cp -R "$app" "$dest/"
verify_bundle "$dest/Nubrix.app"
echo "Installed $dest/Nubrix.app"

if [ -x "$root/scripts/install-hooks.sh" ]; then
  "$root/scripts/install-hooks.sh"
fi

if [ "$open_after" = 1 ]; then
  open "$dest/Nubrix.app"
fi
