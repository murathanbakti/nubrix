#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
derived="${NUBRIX_DERIVED_DATA:-$HOME/Library/Caches/Nubrix/DerivedData}"
dest="${NUBRIX_INSTALL_DIR:-/Applications}"
open_after=0
[ "${1:-}" = "--open" ] && open_after=1

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

identity="${NUBRIX_SIGN_IDENTITY-}"
if [ -z "$identity" ]; then
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  identity="$(awk '/"Apple Development: / { print $2; exit }' <<< "$identities")"
  [ -n "$identity" ] || identity="$(awk '/"Developer ID Application: / { print $2; exit }' <<< "$identities")"
fi
if [ -n "$identity" ] && [ "$identity" != "-" ]; then
  echo "Signing with your local code signing certificate…"
  if ! NUBRIX_SIGN_IDENTITY="$identity" NUBRIX_SIGN_LOCAL=1 "$root/scripts/sign-release.sh" "$app" > "$(dirname "$log")/sign.log" 2>&1; then
    cat "$(dirname "$log")/sign.log" >&2
    echo "Signing failed. Set NUBRIX_SIGN_IDENTITY=- to install with an ad-hoc signature." >&2
    exit 1
  fi
else
  echo "No code signing certificate found, using an ad-hoc signature (macOS may ask for Keychain access and permissions again after each install)."
fi

"$root/scripts/verify-bundle.sh" "$app"

if pgrep -xq Nubrix; then
  echo "Quitting the running Nubrix…"
  pkill -TERM -x Nubrix || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq Nubrix || break; sleep 0.5; done
  pkill -KILL -x Nubrix || true
fi
pkill -TERM -f "$dest/Nubrix.app/Contents/Resources/mediaremote-adapter.pl" || true

target="$dest/Nubrix.app"
staged="$dest/.Nubrix.app.new.$$"
old="$dest/.Nubrix.app.old.$$"
[ -d "$dest" ] && [ -w "$dest" ] || { echo "$dest is not a writable directory (set NUBRIX_INSTALL_DIR)" >&2; exit 1; }
rm -rf "$staged" "$old"
if ! cp -R "$app" "$staged"; then
  rm -rf "$staged"
  echo "Could not copy the app into $dest" >&2
  exit 1
fi
if [ -e "$target" ] || [ -L "$target" ]; then
  if ! mv "$target" "$old"; then
    rm -rf "$staged"
    echo "Could not move the existing $target aside" >&2
    exit 1
  fi
fi
if ! mv "$staged" "$target"; then
  rm -rf "$staged"
  if [ -e "$old" ]; then
    if mv "$old" "$target"; then
      echo "Could not move the new app into place; the previous Nubrix was restored" >&2
    else
      echo "Could not move the new app into place and could not restore the previous Nubrix; it is kept at $old" >&2
    fi
  else
    echo "Could not move the new app into place at $target" >&2
  fi
  exit 1
fi
rm -rf "$old"
"$root/scripts/verify-bundle.sh" "$target"
echo "Installed $dest/Nubrix.app"

if [ -x "$root/scripts/install-hooks.sh" ]; then
  "$root/scripts/install-hooks.sh"
fi

if [ "$open_after" = 1 ]; then
  open "$dest/Nubrix.app"
fi
