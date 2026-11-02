#!/bin/bash
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <path-to-Nubrix.app>" >&2; exit 2; }
b="${1%/}"

expected_xpc="NubrixHelper.xpc"
expected_frameworks="Lottie.framework MediaRemoteAdapter.framework"
expected_macho=(
  "Contents/MacOS/Nubrix"
  "Contents/XPCServices/NubrixHelper.xpc/Contents/MacOS/NubrixHelper"
  "Contents/Frameworks/Lottie.framework/Versions/A/Lottie"
  "Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"
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

entitlements="$(codesign -d --entitlements :- "$b/Contents/XPCServices/$expected_xpc" 2>/dev/null)"
! grep -q 'com.apple.security.get-task-allow' <<< "$entitlements" || fail "get-task-allow is present in the helper"
