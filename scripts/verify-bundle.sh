#!/bin/bash
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <path-to-Nubrix.app>" >&2; exit 2; }
b="${1%/}"

expected_xpc="NubrixHelper.xpc"
expected_frameworks="Lottie.framework MediaRemoteAdapter.framework Sparkle.framework"
expected_macho=(
  "Contents/MacOS/Nubrix"
  "Contents/XPCServices/NubrixHelper.xpc/Contents/MacOS/NubrixHelper"
  "Contents/Frameworks/Lottie.framework/Versions/A/Lottie"
  "Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"
  "Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
  "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
  "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  "Contents/Resources/MediaRemoteAdapterTestClient"
)
hook_files=(
  "scripts/install-hooks.sh"
  "claude-plugin/scripts/nubrix-hook"
  "claude-plugin/scripts/nubrix-permission"
  "claude-plugin/scripts/nubrix-statusline"
  "cli/notchctl"
)

fail() {
  echo "Bundle check failed: $*" >&2
  exit 1
}

[ -d "$b" ] || fail "missing $b"

xpc="$(find "$b/Contents/XPCServices" -mindepth 1 -maxdepth 1 -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//' || true)"
[ "$xpc" = "$expected_xpc" ] || fail "XPCServices is '$xpc', expected '$expected_xpc'"

frameworks="$(find "$b/Contents/Frameworks" -mindepth 1 -maxdepth 1 -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//' || true)"
[ "$frameworks" = "$expected_frameworks" ] || fail "Frameworks is '$frameworks', expected '$expected_frameworks'"

sparkle="$b/Contents/Frameworks/Sparkle.framework"
[ "$(readlink "$sparkle/Versions/Current" 2>/dev/null || true)" = "B" ] || fail "Sparkle.framework Versions/Current is not B"
sparkle_xpc="$(find "$sparkle/Versions/B/XPCServices" -mindepth 1 -maxdepth 1 -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//' || true)"
[ "$sparkle_xpc" = "Installer.xpc" ] || fail "Sparkle XPCServices is '$sparkle_xpc', expected 'Installer.xpc'"

plist="$b/Contents/Info.plist"
pl() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null; }
bundle_id="$(pl CFBundleIdentifier)" || fail "no CFBundleIdentifier"
[ "$(pl SUFeedURL || true)" = "https://github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml" ] || fail "SUFeedURL is wrong"
public_key="$(pl SUPublicEDKey || true)"
if [ -n "$public_key" ]; then
  [[ "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "SUPublicEDKey is not a 32-byte base64 key"
elif [ "${NUBRIX_REQUIRE_SPARKLE_KEY:-0}" = 1 ]; then
  fail "SUPublicEDKey is empty; run scripts/setup-sparkle-key.sh and commit Nubrix/Info.plist before a release"
else
  echo "Note: SUPublicEDKey is empty, so this build reports updates as unavailable" >&2
fi
for k in SUEnableInstallerLauncherService SUVerifyUpdateBeforeExtraction SURequireSignedFeed; do
  [ "$(pl "$k" || true)" = true ] || fail "$k must be true"
done
for k in SUEnableAutomaticChecks SUAutomaticallyUpdate SUEnableSystemProfiling SUShowReleaseNotes; do
  [ "$(pl "$k" || true)" = false ] || fail "$k must be false"
done
for k in SUEnableDownloaderService SUAllowsAutomaticUpdates SUScheduledCheckInterval SUSignedFeedFailureExpirationInterval; do
  ! pl "$k" >/dev/null || fail "$k must not be set"
done

stale_all="$(find "$b" -iname '*boring*')"
stale="$(sed -n '1,5p' <<< "$stale_all")"
[ -z "$stale" ] || fail "stale upstream files: $stale"

root_real="$(cd "$b" && pwd -P)"
links="$(find "$b" -type l)"
while IFS= read -r link; do
  [ -n "$link" ] || continue
  link_target="$(readlink "$link")"
  if [ -d "$link" ]; then
    resolved="$(cd "$link" 2>/dev/null && pwd -P)" || fail "cannot resolve symlink ${link#"$b"/}"
  else
    case "$link_target" in
      /*) parent="$(dirname "$link_target")" ;;
      *) parent="$(dirname "$link")/$(dirname "$link_target")" ;;
    esac
    parent_real="$(cd "$parent" 2>/dev/null && pwd -P)" || fail "cannot resolve symlink ${link#"$b"/}"
    resolved="$parent_real/$(basename "$link_target")"
  fi
  case "$resolved" in
    "$root_real" | "$root_real"/*) ;;
    *) fail "symlink ${link#"$b"/} points outside the bundle ($link_target)" ;;
  esac
done <<< "$links"

regular="$(find "$b" -type f)"
found_macho=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  kind="$(file -b "$f" 2>/dev/null || true)"
  case "$kind" in
    Mach-O*) found_macho+=("${f#"$b"/}") ;;
  esac
done <<< "$regular"

for rel in ${found_macho[@]+"${found_macho[@]}"}; do
  allowed=0
  for want in "${expected_macho[@]}"; do
    [ "$rel" = "$want" ] && allowed=1
  done
  [ "$allowed" = 1 ] || fail "unexpected Mach-O file $rel"
done
for want in "${expected_macho[@]}"; do
  present=0
  for rel in ${found_macho[@]+"${found_macho[@]}"}; do
    [ "$rel" = "$want" ] && present=1
  done
  [ "$present" = 1 ] || fail "missing Mach-O file $want"
done

for rel in "${hook_files[@]}"; do
  f="$b/Contents/Resources/nubrix-hooks/$rel"
  [ -f "$f" ] || fail "missing hook kit file $rel"
  [ -x "$f" ] || fail "hook kit file $rel is not executable"
done

codesign --verify --strict --deep "$b" >/dev/null 2>&1 || fail "codesign verification failed"
details="$(codesign -dv "$b" 2>&1)"
grep -q 'flags=.*runtime' <<< "$details" || fail "hardened runtime is off"

entitlements="$(codesign -d --entitlements :- "$b" 2>/dev/null)"
! grep -q 'com.apple.security.get-task-allow' <<< "$entitlements" || fail "get-task-allow is present"
grep -q 'com.apple.security.cs.disable-library-validation' <<< "$entitlements" || fail "disable-library-validation is missing"
ent_file="$(mktemp "${TMPDIR:-/tmp}/nubrix-verify.XXXXXX")"
trap 'rm -f "$ent_file"' EXIT
printf '%s' "$entitlements" > "$ent_file"
lookup_key="com.apple.security.temporary-exception.mach-lookup.global-name"
lookup() { /usr/libexec/PlistBuddy -c "Print :$lookup_key:$1" "$ent_file" 2>/dev/null; }
[ "$(lookup 0 || true)" = "$bundle_id-spks" ] && [ "$(lookup 1 || true)" = "$bundle_id-spki" ] && ! lookup 2 > /dev/null \
  || fail "mach-lookup exception must list exactly $bundle_id-spks and $bundle_id-spki"

entitlements="$(codesign -d --entitlements :- "$b/Contents/XPCServices/$expected_xpc" 2>/dev/null)"
! grep -q 'com.apple.security.get-task-allow' <<< "$entitlements" || fail "get-task-allow is present in the helper"
