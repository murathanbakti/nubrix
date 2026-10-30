#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
derived="${NUBRIX_DERIVED_DATA:-$root/build/DerivedData}"
dest="${NUBRIX_INSTALL_DIR:-/Applications}"
open_after=0
[ "${1:-}" = "--open" ] && open_after=1

echo "Building Nubrix (Release)…"
xcodebuild -quiet \
  -project "$root/boringNotch.xcodeproj" \
  -scheme boringNotch \
  -configuration Release \
  -derivedDataPath "$derived" \
  -destination "platform=macOS,arch=$(uname -m)" \
  build

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
