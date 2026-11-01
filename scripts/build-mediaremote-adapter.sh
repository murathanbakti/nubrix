#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
repo="https://github.com/ungive/mediaremote-adapter"
tag="v0.7.2"
commit="dc3ff1740e2035a2490ec67d3b33322449af780a"
min_macos="14.0"
dest="$root/mediaremote-adapter"
framework="$dest/MediaRemoteAdapter.framework"

fail() {
  echo "build-mediaremote-adapter: $*" >&2
  exit 1
}

[ -d "$framework" ] || fail "missing $framework"

work="$(mktemp -d "${TMPDIR:-/tmp}/mediaremote-adapter.XXXXXX")"
trap 'rm -rf "${work:?}"' EXIT

git clone --quiet --branch "$tag" --depth 1 "$repo" "$work/src"
actual="$(git -C "$work/src" rev-parse HEAD)"
[ "$actual" = "$commit" ] || fail "$tag resolves to $actual, expected $commit"

cd "$work/src"
sources=()
while IFS= read -r file; do
  sources+=("$file")
done < <(sed -n '/set(ADAPTER_SOURCES/,/)/p' CMakeLists.txt | grep -o 'src/[^ )]*\.m')
[ "${#sources[@]}" -gt 0 ] || fail "no adapter sources found in CMakeLists.txt"

common=(-arch x86_64 -arch arm64 -mmacosx-version-min="$min_macos" -Werror=unguarded-availability-new -fobjc-arc)

xcrun clang "${common[@]}" -Iinclude -Isrc -dynamiclib \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -framework Foundation -framework AppKit -framework JavaScriptCore -framework UniformTypeIdentifiers \
  "${sources[@]}" -o "$work/MediaRemoteAdapter"

xcrun clang "${common[@]}" -Isrc/test src/test/main.m src/test/NowPlayingTest.m \
  -framework Foundation -framework MediaPlayer -o "$work/MediaRemoteAdapterTestClient"

cp "$work/MediaRemoteAdapter" "$framework/Versions/A/MediaRemoteAdapter"
cp "$work/MediaRemoteAdapterTestClient" "$dest/MediaRemoteAdapterTestClient"
cp bin/mediaremote-adapter.pl "$dest/mediaremote-adapter.pl"

codesign --force --sign - "$framework"
codesign --force --sign - --identifier MediaRemoteAdapterTestClient "$dest/MediaRemoteAdapterTestClient"

echo "Built $tag ($commit) for macOS $min_macos"
for bin in "$framework/Versions/A/MediaRemoteAdapter" "$dest/MediaRemoteAdapterTestClient"; do
  echo "$(basename "$bin"): $(lipo -archs "$bin"), minos $(vtool -arch arm64 -show-build "$bin" | awk '$1 == "minos" { print $2 }')"
done
shasum -a 256 "$framework/Versions/A/MediaRemoteAdapter" "$dest/MediaRemoteAdapterTestClient" "$dest/mediaremote-adapter.pl" \
  | sed "s|$root/||"
