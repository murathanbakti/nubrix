# Nubrix roadmap

Nubrix is a developer-friendly notch bar for macOS, forked from
an open-source notch app (GPL-3.0; see the README Credits). It adds a
clipboard showcase ("Vitrin") and live Claude Code session status.

Nubrix-specific code lives in `Nubrix/Features/` (a file-system synchronized
group, so new files are picked up by Xcode automatically). Changes to upstream
files are kept small so upstream fixes can be merged.

## Phase 0: Fork and rebrand (done)

- Product name Nubrix, bundle id `dev.nubrix.app`, upstream update feed removed (Sparkle itself was removed later).
- Builds with Xcode 26 on macOS 26 (CI pins 26.6); music control works with ad-hoc signing.

## Phase 1: Claude Code sessions (done)

- `Nubrix/Features/Agents/`: loopback-only HTTP event server, session store, notch views.
- Endpoint, token and pid in `~/.config/nubrix-run/agent-endpoint` (0600, directory 0700).
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
- Hardening (audit 2026-10-31, S-01/02/04/05/06/07/11/12/13/14): hook scripts verify the
  server with an HMAC challenge-response, endpoint file carries the Nubrix pid, scripts are
  installed to `~/.config/nubrix/bin` (`scripts/install-hooks.sh`; the sandboxed app can only read that folder and writes only to `~/.config/nubrix-run`), the token never appears
  in argv, the approval card shows the full command and a content/diff preview, Allow is
  armed after 0.7 s plus pointer movement, prompts are withdrawn on lock/sleep/session
  switch, the HTTP server authenticates on headers and caps connections. Not yet tried on
  device: lock-screen behaviour, hover arming in the non-activating panel, Claude Code's
  dialog while the hook waits.

## Phase 2: Vitrin (clipboard showcase) (done, UI not yet tried on device)

Goal: everything copied (images, text, links) is kept locally and shown as a
showcase, both inside the open notch and in a larger panel.

Data layer (`Nubrix/Features/Clipboard/`):
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
  6379, 8000, 8080, 8888, 9000 …) with short TCP connects every 15 seconds and
  shows which are up in the "Dev" tab; clicking an HTTP port opens it in the
  browser.
- A GitHub module via the `gh` login was dropped (the sandbox cannot use `gh` credentials); it came back as a token-based integration, see below.

## GitHub integration (done, not yet tried against live GitHub)

- `Nubrix/Features/GitHub/`: Keychain token store, URLSession client (GraphQL for PR search,
  REST for Actions runs with ETags, rate-limit headers and Retry-After honoured, redirects
  blocked), polling store (2 min; 30 s while the section is visible or a run is in progress on
  AC power; 7.5 min when quiet; backs off when offline or failing; paused on sleep and lock), change detector that decides which banners and inbox entries fire.
- Dev tab: GitHub / Servers / Notifications switch with Review requested, My PRs and Actions
  columns; Claude session rows show the PR of their branch (`nubrix-hook` sends
  `X-Nubrix-Remote` with the branch); Settings, GitHub holds the token, watched repositories
  and notification toggles; new inbox source `github`.
- Auth is a fine-grained read-only PAT, not the `gh` login or SSH keys (see README).
- Not verified yet: GraphQL `statusCheckRollup` with a fine-grained token (REST fallback is in
  place), the exact set of permission names in GitHub's token form, Keychain prompts after an
  ad hoc re-sign, fork PRs (the session's `origin` is the fork, the PR lives upstream).

## Phase 5: Open source release (local preparation done, publishing pending)

Done locally:
- User-visible rebrand to Nubrix (strings, window titles, onboarding, tips, About
  upstream credits/GPL-3.0); full rename of the Xcode project, targets, Swift
  types, preference keys, identifiers and the XPC helper (`NubrixHelper`), with a
  one-time `NubrixMigration` for old preference keys and the shelf folder.
- Auto-updater removed: Sparkle, its entitlements and the update UI are gone. Nubrix has no updater.
- Original placeholder app icon and in-app logo.
- README, CONTRIBUTING, SECURITY rewritten; upstream workflows, funding and
  Crowdin config removed; `.github/workflows/build.yml` (unsigned Debug build
  plus script and manifest checks).
- Claude Code plugin and manual hooks instructions, notchctl install notes.

Left for publishing:
- Create the GitHub repository and add its URL to the README, About page and issue templates.
- Developer ID signing and notarization; CI-built release DMG.
- Decide on an update mechanism (none exists; Sparkle was removed).
- Encryption at rest for Vitrin (needs stable signing identity for Keychain access).
- Enable GitHub private vulnerability reporting on the repository (SECURITY.md already points to it).
- Screenshots and final app icon.

## Notch extensions

`Nubrix/Features/Shell/NotchExtensionHost` presents content that grows out of the notch
(goo/mitosis transition) in a borderless panel; one extension at a time.
- Mirror: detached mode, the notch splits and the camera panel floats below it.
  Global shortcut ⌃⌥M. The host handles Esc.
- Calendar: attached mode, a sheet that drops from the notch (header date pill
  or ⌃⌥K). The sheet takes key focus on open and activates Nubrix; on close the
  previously frontmost app is re-activated. The calendar owns Esc (cancels a
  form or the go-to field first, closes only when nothing is left to cancel).
- The old in-notch calendar tab and the coordinator overlay API were removed.

## Notifications from other apps (done, being tried on device)

- `NubrixHelper/SystemNotificationReader.swift` reads the macOS notification
  database (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`)
  read-only; new rows are found by `rec_id` and `delivered_date`, only ticked
  apps leave the helper, strings are sanitized and truncated.
- `Nubrix/Features/SystemNotifications/`: polling store (2 s, skipped when the
  file is unchanged, paused while asleep or locked), closed-notch banner, inbox
  source `system`, settings section and the Full Disk Access guide panel with a
  draggable app icon and live detection. Optional onboarding step.
- Off by default; needs Full Disk Access for Nubrix. Content stays in memory.
- Later: a list of recent notifications in the open notch; Dock badge counts
  as a no-permission fallback.
