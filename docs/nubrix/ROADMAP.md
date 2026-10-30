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

## Phase 2: Vitrin (clipboard showcase)

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

## Phase 3: Developer clipboard

- Code detection with syntax highlighting, JSON pretty-print/validate,
  JWT / Base64 / URL decode, Unix timestamp → date, color swatches, UUIDs.
- Encryption at rest (CryptoKit, key in Keychain) once signing is stable.

## Phase 4: Extras

- `notchctl` CLI to post messages to the notch from scripts.
- Listening dev-server ports; GitHub PR / CI summary via `gh`.

## Phase 5: Open source release

- CI-built, signed releases with our own Sparkle feed, README, license notices,
  Claude Code plugin install instructions.
