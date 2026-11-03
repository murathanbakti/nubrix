#!/bin/bash
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <path-to-Nubrix.app>" >&2; exit 2; }
app="${1%/}"
root="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
  echo "strip-sparkle-downloader: $*" >&2
  exit 1
}

services="$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"
[ -d "$services/Installer.xpc" ] || fail "Sparkle's Installer.xpc is missing in $app"

if [ -e "$services/Downloader.xpc" ] || [ -L "$services/Downloader.xpc" ]; then
  rm -rf "$services/Downloader.xpc"
  if ! output="$(NUBRIX_SIGN_IDENTITY=- "$root/scripts/sign-release.sh" "$app" 2>&1)"; then
    echo "$output" >&2
    fail "ad-hoc re-signing failed"
  fi
  echo "Removed Sparkle's Downloader.xpc and re-signed the app ad hoc"
fi

[ "$(ls "$services")" = "Installer.xpc" ] || fail "unexpected Sparkle XPC services: $(ls "$services" | tr '\n' ' ')"
