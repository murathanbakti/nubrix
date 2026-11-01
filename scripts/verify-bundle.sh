#!/bin/bash
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <path-to-Nubrix.app>" >&2; exit 2; }
b="${1%/}"

expected_xpc="NubrixHelper.xpc"
expected_frameworks="Lottie.framework MediaRemoteAdapter.framework"
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

stale="$(find "$b" -iname '*boring*' | head -5)"
[ -z "$stale" ] || fail "stale upstream files: $stale"

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
