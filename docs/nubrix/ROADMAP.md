# Nubrix roadmap

Nubrix is a developer-friendly notch bar for macOS, forked from
[boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0). It adds a
clipboard showcase ("Vitrin") and live Claude Code session status.

Nubrix-specific code lives in `boringNotch/Nubrix/` (a file-system synchronized
group, so new files are picked up by Xcode automatically). Changes to upstream
files are kept small so upstream fixes can be merged.

## Phase 0: Fork and rebrand (done)

- Product name Nubrix, bundle id `dev.nubrix.app`, upstream update feed removed.
- Builds with Xcode 26.2 on macOS 26; music control works with ad-hoc signing.

## Phase 1: Claude Code sessions (done)

- `Nubrix/Agents/`: loopback-only HTTP event server, session store, notch views.
- Endpoint and token in `~/.config/nubrix/agent-endpoint` (0600).
- `claude-plugin/`: async command hooks that forward hook JSON to Nubrix.
- Verified: hooks fire from Claude Code desktop sessions and the CLI.
- Source label (entrypoint, app bundle id, terminal) and git branch per session; click a
  row to activate the source app.
- Status line script forwards context %, cost, model and the 5-hour limit to
  `POST /v1/claude/status`; context bar per row, 5h meter in the tab header, banner and
  inbox entry above 85% context.
- Permission approvals from the notch: synchronous `PermissionRequest` hook
  (`nubrix-permission`) holds `POST /v1/claude/permission` open until Allow / Deny;
  risky commands need a second click; any failure falls back to Claude Code's dialog.
  Not yet tried with the live app and Claude Code.

## Phase 2: Vitrin (clipboard showcase) (done, UI not yet tried on device)

Goal: everything copied (images, text, links) is kept locally and shown as a
showcase, both inside the open notch and in a larger panel.

Data layer (`Nubrix/Clipboard/`):
- `ClipboardMonitor`: polls `NSPasteboard.general.changeCount` (0.5 s). Skips
  concealed / transient / auto-generated pasteboard types and password-manager
  markers; skips Nubrix's own writes; respects `NSPasteboard.accessBehavior`
  on macOS 15.4+ (stop reading when access is denied).
- Classification: standalone web URL → link; text → text; image → image.
  Re-copying identical text refreshes the existing item instead of duplicating.
- Secret guard: text that looks like a credential (private keys, `sk-`,
  `ghp_`/`github_pat_`, `AKIA`, `xox[bap]-`, JWTs, `Bearer …`, long high-entropy
  tokens) is not stored.
- `ClipStore`: SQLite (system `sqlite3`, no new dependencies) in the app's
  Application Support folder, FTS5 search, image files beside the DB, 0600/0700
  permissions. Pinned items never expire; others expire after a retention
  period (default 30 days).
- Ideas and selected code adapted from ClipBoardLine / Tendedero (MIT); the
  MIT notice is kept in `THIRD_PARTY_LICENSES`.

UI:
- Notch tab "Vitrin": filter chips (All / Images / Text / Links) and one
  horizontal row of cards. Click copies (and closes the notch); pin and delete
  on hover and in the context menu.
- Showcase panel (global shortcut, default ⌃⌥V): a larger dark panel under the
  notch with search and three rows (Images, Text, Links), keyboard navigation
  (arrows, Enter copies, P pins, Delete removes, Esc closes).
- Settings → Vitrin: capture toggles per type, retention, excluded apps.

## Phase 3: Developer clipboard (done)

- `ClipInsight`: pure, cached analysis of a text item that yields a badge and
  developer actions. Detects JSON (valid object/array), language of code
  (Swift, TypeScript/JavaScript, Python, Go, Rust, SQL, Shell, YAML, HTML, CSS),
  Base64 that decodes to printable UTF-8, percent-encoded text, Unix timestamps
  (10 or 13 digits within 2000–2100), colors (#RGB, #RRGGBB, #RRGGBBAA,
  rgb()/rgba(), hsl()), UUIDs.
- Cards show the badge (language name, "JSON", a color swatch, the human date
  for a timestamp). Code cards use a lightweight regex syntax highlighter
  (keywords, strings, numbers, comments) on a monospaced font.
- Actions (context menu and showcase panel): Copy pretty JSON, Copy minified
  JSON, Copy decoded (Base64 / URL), Copy ISO date, Copy hex / rgb.
- Showcase panel: Space toggles a large preview of the selected item
  (highlighted code, full image, link details) inside the panel.
- JWT decoding is out of scope: JWTs are blocked by the secret guard.
- Encryption at rest is deferred to Phase 5: with ad-hoc signing every rebuild
  changes the code identity, so Keychain access would prompt after each build.

## Phase 4: Extras (done, UI not yet tried on device)

- `notchctl` CLI (bash + curl, same endpoint and token as the Claude hooks):
  `notchctl notify "Build done" --title api --style success|error|info`,
  `notchctl ping`. The app accepts `POST /v1/notify` and shows a closed-notch
  banner plus a short history in a "Dev" tab. Scripts can then report anything,
  e.g. `gh run watch && notchctl notify "CI green"`.
- Dev servers: the sandbox cannot list other processes, so Nubrix probes a
  configurable list of localhost ports (3000, 3001, 4200, 5000, 5173, 5432,
  6379, 8000, 8080, 8888, 9000 …) with short TCP connects every few seconds and
  shows which are up in the "Dev" tab; clicking an HTTP port opens it in the
  browser.
- A direct GitHub module is dropped: the sandbox cannot use `gh` credentials.

## Phase 5: Open source release (local preparation done, publishing pending)

Done locally:
- User-visible rebrand to Nubrix (strings, window titles, onboarding, tips, About
  credits for boring.notch/GPL-3.0); Swift types, targets, bundle ids and
  persistence paths keep upstream names to ease merges.
- Software-update UI hidden (Sparkle is not started and has no feed).
- Original placeholder app icon and in-app logo.
- README, CONTRIBUTING, SECURITY rewritten; upstream workflows, funding and
  Crowdin config removed; `.github/workflows/build.yml` (unsigned Debug build
  plus script and manifest checks).
- Claude Code plugin and manual hooks instructions, notchctl install notes.

Left for publishing:
- Create the GitHub repository and add its URL to the README, About page and issue templates.
- Developer ID signing and notarization; CI-built release DMG.
- Own Sparkle feed and EdDSA keys, then re-enable the updater UI.
- Encryption at rest for Vitrin (needs stable signing identity for Keychain access).
- Private vulnerability reporting channel.
- Screenshots, final app icon, and `CFBundleDisplayName`/`CFBundleName` in the
  Xcode project (still "Boring Notch").

## Notch extensions

`Nubrix/Shell/NotchExtensionHost` presents content that grows out of the notch
(goo/mitosis transition) in a borderless panel; one extension at a time.
- Mirror: detached mode, the notch splits and the camera panel floats below it.
  Global shortcut ⌃⌥M. The host handles Esc.
- Calendar: attached mode, a sheet that drops from the notch (header date pill
  or ⌃⌥K). The sheet takes key focus on open and activates Nubrix; on close the
  previously frontmost app is re-activated. The calendar owns Esc (cancels a
  form or the go-to field first, closes only when nothing is left to cancel).
- The old in-notch calendar tab and the coordinator overlay API were removed.
