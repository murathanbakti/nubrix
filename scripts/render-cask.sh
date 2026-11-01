#!/bin/bash
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 <version> <sha256>" >&2; exit 2; }
version="$1"
sha="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid version: $version" >&2; exit 2; }
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid sha256: $sha" >&2; exit 2; }

sed -e "s/@VERSION@/$version/" -e "s/@SHA256@/$sha/" "$root/packaging/homebrew/nubrix.rb.template"
