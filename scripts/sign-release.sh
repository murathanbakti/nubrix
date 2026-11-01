#!/bin/bash
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <path-to-Nubrix.app>" >&2; exit 2; }
app="${1%/}"
identity="${NUBRIX_SIGN_IDENTITY:?set NUBRIX_SIGN_IDENTITY to a Developer ID Application identity, or - for an ad-hoc dry run}"
team="${NUBRIX_TEAM_ID:-}"
keychain="${NUBRIX_SIGN_KEYCHAIN:-}"

fail() {
  echo "sign-release: $*" >&2
  exit 1
}

[ -d "$app/Contents" ] || fail "not an app bundle: $app"
if [ "$identity" != "-" ]; then
  [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || fail "NUBRIX_TEAM_ID must be a 10 character Apple team ID"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/nubrix-sign.XXXXXX")"
trap 'rm -rf "$work"' EXIT

is_macho() {
  case "$(file -b "$1")" in
    Mach-O*) return 0 ;;
    *) return 1 ;;
  esac
}

sign() {
  local target="$1" ent="$work/entitlements.plist"
  local args=(--force --sign "$identity" --options runtime)
  if [ "$identity" = "-" ]; then
    args+=(--timestamp=none)
  else
    args+=(--timestamp)
  fi
  [ -z "$keychain" ] || args+=(--keychain "$keychain")

  rm -f "$ent"
  codesign -d --entitlements "$ent" --xml "$target" >/dev/null 2>&1 || true
  if [ -s "$ent" ]; then
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$ent" >/dev/null 2>&1 || true
    args+=(--entitlements "$ent")
  fi

  codesign "${args[@]}" "$target" || fail "codesign failed for $target"
  if [ "$target" = "$app" ]; then echo "signed     $(basename "$app")"; else echo "signed     ${target#"$app"/}"; fi
}

loose=()
while IFS= read -r -d '' f; do
  is_macho "$f" && loose+=("$f")
done < <(find "$app/Contents/Resources" "$app/Contents/Helpers" "$app/Contents/Library" -type f -print0 2>/dev/null)

for f in ${loose[@]+"${loose[@]}"}; do
  sign "$f"
done

shopt -s nullglob
for fw in "$app"/Contents/Frameworks/*.framework "$app"/Contents/Frameworks/*.dylib; do
  sign "$fw"
done
for xpc in "$app"/Contents/XPCServices/*.xpc; do
  sign "$xpc"
done
shopt -u nullglob
sign "$app"

codesign --verify --strict --deep --verbose=2 "$app" >/dev/null 2>&1 || fail "codesign --verify failed after signing"

hook_files=(
  "scripts/install-hooks.sh"
  "claude-plugin/scripts/nubrix-hook"
  "claude-plugin/scripts/nubrix-permission"
  "claude-plugin/scripts/nubrix-statusline"
  "cli/notchctl"
)
seal="$app/Contents/_CodeSignature/CodeResources"
for rel in "${hook_files[@]}"; do
  /usr/libexec/PlistBuddy -c "Print :files2:Resources/nubrix-hooks/$rel" "$seal" >/dev/null 2>&1 \
    || fail "hook kit file $rel is not sealed by the app signature"
done

checked=0
while IFS= read -r -d '' f; do
  is_macho "$f" || continue
  details="$(codesign -dvv "$f" 2>&1)" || fail "unsigned code: ${f#"$app"/}"
  grep -q 'flags=.*runtime' <<< "$details" || fail "hardened runtime is off: ${f#"$app"/}"
  entitlements="$(codesign -d --entitlements - --xml "$f" 2>/dev/null || true)"
  ! grep -q 'com.apple.security.get-task-allow' <<< "$entitlements" || fail "get-task-allow is present: ${f#"$app"/}"
  if [ "$identity" != "-" ]; then
    grep -q '^Authority=Developer ID Application: ' <<< "$details" || fail "not signed with Developer ID: ${f#"$app"/}"
    grep -qx "TeamIdentifier=$team" <<< "$details" || fail "team is not $team: ${f#"$app"/}"
    grep -q '^Timestamp=' <<< "$details" || fail "no secure timestamp: ${f#"$app"/}"
  fi
  checked=$((checked + 1))
done < <(find "$app" -type f -print0)

[ "$checked" -gt 0 ] || fail "no code found in $app"
if [ "$identity" = "-" ]; then
  echo "Ad-hoc dry run: $checked Mach-O files re-signed with the hardened runtime"
else
  echo "Developer ID ($team): $checked Mach-O files signed with the hardened runtime and a secure timestamp"
fi
