# Images

The README images are rendered from HTML mockups in [`mockups/`](mockups), not captured from a running app. The mockups follow the SwiftUI source (sizes, fonts, colors, radii) and use sample data only: the `acme` organization, made-up branches, people, events and a fictional track. Nothing in them comes from a real account, clipboard, calendar or repository.

| File | Scene | Shows |
|---|---|---|
| `hero.png` | `hero.html` | The open notch on the Home tab: music player and the Claude plan usage card |
| `claude-sessions.png` | `claude-sessions.html` | The Claude tab with Needs you, Working, Done and Idle sessions, source labels, branches, context bars and a PR chip |
| `permission-approval.png` | `permission-approval.html` | A Bash permission card with Deny and Allow, and a risky command in the "Allow anyway" state |
| `vitrin.png` | `vitrin.html` | The Vitrin tab with filter chips, cards and the actions menu of a JSON item |
| `vitrin-panel.png` | `vitrin-panel.html` | The Vitrin showcase panel with search and rows, and the Space preview with developer-insight actions |
| `dev-github.png` | `dev-github.html` | The Dev tab on the GitHub switch: review requests, my PRs and Actions runs |
| `dev-servers.png` | `dev-servers.html` | The Dev tab on the Servers and Notifications switches |
| `closed-notch.png` | `closed-notch.html` | Closed-notch states: Claude activity and banners, notchctl, GitHub, screenshot and meeting |
| `music.png` | `music.html` | Closed-notch music activity, the inline volume HUD and the open player with a lyric line |
| `shelf.png` | `shelf.html` | The shelf tab with the quick-share zone and files |
| `calendar.png` | `calendar.html` | The calendar sheet with the month grid and the day panel |

## Rendering

`mockups/render.sh` renders every scene, or only the scenes you name, with headless Google Chrome and writes `docs/images/<scene>.png`. The device scale factor is chosen so each image is 1800 px wide (at most 2x), enough for the README width of about 830 px on a Retina display; set `MAX_WIDTH` to change it:

```sh
docs/images/mockups/render.sh
docs/images/mockups/render.sh hero vitrin
```

Each scene sets its size in a `data-size="WxH"` attribute on its root element. Shared styles are in `mockups/kit.css` and icons in `mockups/icons.js`; icons are hand-drawn or Lucide-style SVG, not SF Symbols. `render.sh` runs `optimize_png.py` for a lossless re-encode when Python 3 and numpy are available.

When you change the UI, update the matching scene and re-render. Keep the text legible at the README width of about 830 px (about 9 px or larger after scaling) and each PNG under 1 MB. Use sample data only: no real names, emails, tokens, repositories, home paths or private commands.

## Still to capture

`gatekeeper-open-anyway.png` for the First launch section is a real screenshot of System Settings, Privacy & Security, with the "Open Anyway" button, not a mockup.
