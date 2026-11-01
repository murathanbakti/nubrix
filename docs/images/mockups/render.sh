#!/usr/bin/env bash
set -euo pipefail

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(cd "$HERE/.." && pwd)"
MAX_WIDTH="${MAX_WIDTH:-1800}"

if [ ! -x "$CHROME" ]; then
  echo "Google Chrome not found at: $CHROME" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  scenes=("$@")
else
  scenes=()
  for f in "$HERE"/*.html; do scenes+=("$(basename "$f" .html)"); done
fi

for scene in "${scenes[@]}"; do
  scene="${scene%.html}"
  file="$HERE/$scene.html"
  if [ ! -f "$file" ]; then echo "No such scene: $file" >&2; exit 1; fi
  size="$(grep -o 'data-size="[0-9]*x[0-9]*"' "$file" | head -1 | sed -E 's/data-size="([0-9]+)x([0-9]+)"/\1,\2/')"
  if [ -z "$size" ]; then echo "$scene.html has no data-size=\"WxH\"" >&2; exit 1; fi
  scale="$(awk -v w="${size%,*}" -v m="$MAX_WIDTH" 'BEGIN { s = m / w; if (s > 2) s = 2; printf "%.4f", s }')"
  profile="$(mktemp -d)"
  out="$OUT_DIR/$scene.png"
  echo "Rendering $scene ($size @${scale}x) -> $out"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor="$scale" \
    --window-size="$size" --user-data-dir="$profile" --screenshot="$out" "file://$file" >/dev/null 2>&1 || true
  rm -rf "${profile:?}"
  if [ ! -s "$out" ]; then echo "Render failed for $scene" >&2; exit 1; fi
  python3 "$HERE/optimize_png.py" "$out" 2>/dev/null || true
done
