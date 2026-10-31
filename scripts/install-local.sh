#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
derived="${NUBRIX_DERIVED_DATA:-$HOME/Library/Caches/Nubrix/DerivedData}"
dest="${NUBRIX_INSTALL_DIR:-/Applications}"
open_after=0
[ "${1:-}" = "--open" ] && open_after=1

log="$(dirname "$derived")/build.log"
mkdir -p "$(dirname "$log")"
echo "Building Nubrix (Release)…"
if ! xcodebuild -quiet \
  -project "$root/Nubrix.xcodeproj" \
  -scheme Nubrix \
  -configuration Release \
  -derivedDataPath "$derived" \
  -destination "platform=macOS,arch=$(uname -m)" \
  ENABLE_HARDENED_RUNTIME=NO \
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

if pgrep -xq Nubrix; then
  echo "Quitting the running Nubrix…"
  pkill -x Nubrix || true
  for _ in 1 2 3 4; do pgrep -xq Nubrix || break; sleep 0.5; done
  pkill -9 -x Nubrix || true
fi

rm -rf "$dest/Nubrix.app"
cp -R "$app" "$dest/"
echo "Installed $dest/Nubrix.app"

if [ "$open_after" = 1 ]; then
  open "$dest/Nubrix.app"
fi
