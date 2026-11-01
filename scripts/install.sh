#!/bin/bash
set -euo pipefail

main() {

repo="murathanbakti/nubrix"
bundle_id="dev.nubrix.app"
base_url="${NUBRIX_RELEASE_BASE_URL:-https://github.com/$repo/releases/download}"
dest="${NUBRIX_INSTALL_DIR:-/Applications}"
version="${NUBRIX_VERSION:-}"
version="${version#v}"

fail() {
  echo "Nubrix install failed: $*" >&2
  exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "Nubrix only runs on macOS"
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$macos_major" -ge 14 ] || fail "Nubrix needs macOS 14 or later (this Mac runs $(sw_vers -productVersion))"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/nubrix-install.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

proto="=https"
case "$base_url" in
  file://*) proto="=file" ;;
  https://*) ;;
  *) fail "NUBRIX_RELEASE_BASE_URL must start with https:// or file://" ;;
esac

fetch() {
  curl --fail --silent --show-error --location --proto "$proto" --proto-redir "$proto" --output "$2" "$1" </dev/null
}

if [ -z "$version" ]; then
  echo "Looking up the latest Nubrix release…"
  curl --fail --silent --show-error --location --proto "=https" --proto-redir "=https" \
    --header "Accept: application/vnd.github+json" \
    --output "$tmp/latest.json" "https://api.github.com/repos/$repo/releases/latest" </dev/null \
    || fail "could not query the latest release (no release published yet? set NUBRIX_VERSION)"
  tag="$(plutil -extract tag_name raw -o - "$tmp/latest.json" 2>/dev/null || true)"
  version="${tag#v}"
fi
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "unexpected version '$version'"

zip="Nubrix-$version.zip"
echo "Installing Nubrix $version into $dest"

fetch "$base_url/v$version/$zip" "$tmp/$zip" || fail "could not download $zip"
fetch "$base_url/v$version/$zip.sha256" "$tmp/$zip.sha256" || fail "could not download $zip.sha256"

listed_name="$(awk 'NR == 1 { print $2 }' "$tmp/$zip.sha256")"
[ "$listed_name" = "$zip" ] || fail "$zip.sha256 describes '$listed_name', not $zip"
(cd "$tmp" && shasum -a 256 -c "$zip.sha256" >/dev/null 2>&1) || fail "SHA-256 mismatch for $zip"
actual="$(shasum -a 256 "$tmp/$zip" | awk '{ print $1 }')"
if [ -n "${NUBRIX_SHA256:-}" ]; then
  [ "$actual" = "$NUBRIX_SHA256" ] || fail "SHA-256 $actual does not match NUBRIX_SHA256"
fi
echo "SHA-256 $actual"

mkdir "$tmp/extract"
ditto -x -k "$tmp/$zip" "$tmp/extract" || fail "could not unpack $zip"
app="$tmp/extract/Nubrix.app"
[ -d "$app" ] || fail "Nubrix.app is missing from $zip"

found_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
[ "$found_id" = "$bundle_id" ] || fail "bundle identifier is '$found_id', expected '$bundle_id'"
found_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[ "$found_version" = "$version" ] || fail "app version is '$found_version', expected '$version'"
codesign --verify --strict --deep "$app" >/dev/null 2>&1 || fail "code signature does not verify"

mkdir -p "$dest" || fail "cannot create $dest"
[ -w "$dest" ] || fail "$dest is not writable (set NUBRIX_INSTALL_DIR or use sudo)"

target="$dest/Nubrix.app"
running=()
while read -r pid; do
  [ -n "$pid" ] || continue
  case "$(ps -p "$pid" -o comm= 2>/dev/null)" in
    "$target"/Contents/MacOS/*) running+=("$pid") ;;
  esac
done < <(pgrep -x Nubrix || true)
if [ "${#running[@]}" -gt 0 ]; then
  echo "Quitting the running Nubrix…"
  kill -TERM "${running[@]}" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    alive=0
    for pid in "${running[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then alive=1; fi
    done
    [ "$alive" = 0 ] && break
    sleep 0.5
  done
  kill -KILL "${running[@]}" 2>/dev/null || true
fi
pkill -TERM -f "$target/Contents/Resources/mediaremote-adapter.pl" || true

staged="$dest/.Nubrix.app.new.$$"
rm -rf "$staged"
ditto "$app" "$staged" || fail "could not copy the app into $dest"
rm -rf "$target"
mv "$staged" "$target"
codesign --verify --strict --deep "$target" >/dev/null 2>&1 || fail "installed app does not verify"

cat <<TXT

Installed $target ($version)

Nubrix is ad-hoc signed and not notarized by Apple. Because curl downloaded
it, the app carries no quarantine flag and macOS will not show the Gatekeeper
prompt. Integrity comes from HTTPS, the published SHA-256 and the code
signature check done above. Set NUBRIX_SHA256 to pin the expected hash.

Optional next step, Claude Code hooks (prints a snippet for ~/.claude/settings.json,
never edits it):

  "$target/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh"

Then open Nubrix:  open "$target"
TXT
}

main "$@"
