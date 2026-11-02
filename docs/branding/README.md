# Branding

The Nubrix mark is an N made of two pills with a Claude-orange diagonal. The app icon puts it on a graphite macOS rounded square with the MacBook notch at the top. The wordmark is hand-drawn round-cap lettering, not a font, and the dot on the i is the orange "live" dot.

| File | Use |
| --- | --- |
| `nubrix-logo.svg`, `nubrix-logo-dark.svg` | Mark and wordmark, for light and dark backgrounds |
| `nubrix-mark.svg`, `nubrix-mark-dark.svg` | The N alone |
| `nubrix-wordmark.svg`, `nubrix-wordmark-dark.svg` | "nubrix" alone |
| `nubrix-app-icon.svg` | App icon source for 64 px and up |
| `nubrix-app-icon-small.svg` | App icon source for 16 and 32 px: heavier strokes, no notch |
| `concepts/` | The directions that were considered |

Colors: orange `#d97857` (Claude accent), ink `#111114` on light, `#f4f4f6` on dark.

## Regenerating the app icon

`Nubrix/Assets.xcassets/AppIcon.appiconset` is rendered from the two app icon SVGs with headless Chrome. The 16x16 (1x and 2x) and 32x32 (1x) PNGs come from `nubrix-app-icon-small.svg` and every other size from `nubrix-app-icon.svg`:

```sh
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
render() {
  page="$(mktemp -d)/icon.html"; profile="$(mktemp -d)"
  printf '<html><body style="margin:0;background:transparent"><img src="file://%s" width="%s" height="%s" style="display:block"></body></html>' "$PWD/$1" "$2" "$2" > "$page"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size="$2,$2" --user-data-dir="$profile" \
    --allow-file-access-from-files --screenshot="$PWD/$3" "file://$page" >/dev/null 2>&1
  rm -rf "$profile" "$(dirname "$page")"
}
set=Nubrix/Assets.xcassets/AppIcon.appiconset
render docs/branding/nubrix-app-icon-small.svg 16 $set/icon_16x16.png
render docs/branding/nubrix-app-icon-small.svg 32 $set/icon_16x16@2x.png
render docs/branding/nubrix-app-icon-small.svg 32 $set/icon_32x32.png
render docs/branding/nubrix-app-icon.svg 64 $set/icon_32x32@2x.png
render docs/branding/nubrix-app-icon.svg 128 $set/icon_128x128.png
render docs/branding/nubrix-app-icon.svg 256 $set/icon_128x128@2x.png
render docs/branding/nubrix-app-icon.svg 256 $set/icon_256x256.png
render docs/branding/nubrix-app-icon.svg 512 $set/icon_256x256@2x.png
render docs/branding/nubrix-app-icon.svg 512 $set/icon_512x512.png
render docs/branding/nubrix-app-icon.svg 1024 $set/icon_512x512@2x.png
```
