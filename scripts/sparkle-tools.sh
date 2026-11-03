#!/bin/bash
set -euo pipefail

version="2.10.1"
sha256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
url="https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"

fail() {
  echo "sparkle-tools: $*" >&2
  exit 1
}

[ $# -eq 1 ] || { echo "usage: $0 <empty-or-new-directory>" >&2; exit 2; }
dest="$1"
[ ! -e "$dest" ] || [ -z "$(ls -A "$dest")" ] || fail "$dest is not empty"
mkdir -p "$dest"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/nubrix-sparkle.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$tmp/sparkle.tar.xz" "$url" || fail "download failed: $url"
got="$(shasum -a 256 "$tmp/sparkle.tar.xz" | awk '{ print $1 }')"
[ "$got" = "$sha256" ] || fail "SHA-256 mismatch for Sparkle-$version.tar.xz: got $got"

tar -xJf "$tmp/sparkle.tar.xz" -C "$dest" ./bin/generate_appcast ./bin/sign_update ./bin/generate_keys ./LICENSE
for tool in generate_appcast sign_update generate_keys; do
  f="$dest/bin/$tool"
  [ -f "$f" ] && [ ! -L "$f" ] || fail "missing $tool in the archive"
  chmod 755 "$f"
  case " $(lipo -archs "$f") " in
    *" $(uname -m) "*) ;;
    *) fail "$tool has no $(uname -m) slice" ;;
  esac
done
printf '%s\n' "$dest/bin"
