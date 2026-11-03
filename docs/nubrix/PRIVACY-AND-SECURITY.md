# Privacy and security

How Nubrix keeps your data on your Mac and limits what each part can do. For a summary, see the [README](../../README.md#privacy-and-security). To report a problem, see [SECURITY.md](../../SECURITY.md).

## Local only

Everything stays on your Mac. Nubrix has no analytics, no account and sends nothing to a Nubrix server. It has no auto-updater: an optional daily check (off until you turn it on) only asks GitHub for the latest version number, and Nubrix never downloads or installs anything.

## Network use

The complete list:

- `api.github.com`, only if you add a fine-grained read-only token (off until then; see [GitHub integration](../../README.md#github-integration)). The token goes nowhere else.
- `api.github.com/repos/murathanbakti/nubrix/releases/latest`, when you press Check now or turn on the daily update check in Settings, About, Updates (off by default). The request carries no token or cookies and nothing beyond your IP address and `User-Agent: Nubrix/<version>`. Redirects are refused and only the release's `tag_name` is read, as a version number. Nothing is downloaded or run. Stored on your Mac: the date of the last check, the latest version seen and a version you skipped.
- `lrclib.net` receives the track title and artist when lyrics are turned on (off by default).
- LottieFiles: a visualizer animation (JSON) is downloaded when the built-in music visualizer is turned off in Settings.
- Artwork URLs supplied by Spotify or YouTube Music are fetched to show the cover.
- `localhost:26538`, the local API of the YouTube Music desktop app, when that controller is used.
- The `claude` command-line tool, run by the helper to read your plan usage (see [Usage, context and cost](CLAUDE-CODE.md#usage-context-and-cost)); Claude itself talks to Anthropic as it always does. Turn it off in Settings, Notifications, Claude Code.

## Sandbox and helper split

The app is sandboxed. The only unsandboxed part is the small XPC service `NubrixHelper`, used for Accessibility-based key handling, brightness, the `claude /usage` probe and, when turned on, the read-only reader of the macOS notification database. The app can read `~/.config/nubrix/` (the sealed hook scripts) but cannot write there, so it cannot change what Claude Code runs; its only writable config location is `~/.config/nubrix-run/`.

The entitlements allow Apple Events only to Spotify, Music, Terminal, iTerm and Ghostty. To find a Claude session's tab, the scripts get only a checked terminal device name (`/dev/ttysNNN`) and, for Ghostty, the session folder passed as a script parameter, never as script text. A Warp session link from the hook is opened only in the exact `warp…://session/<32 hex>` form and only when the app that handles it is a `dev.warp.*` app.

## Local endpoint

The event server binds to the loopback interface only (127.0.0.1) on a random port, authenticates on request headers with a random bearer token and caps connections. Port, token and process id are written to `~/.config/nubrix-run/agent-endpoint` (file 0600 in a 0700 directory). Hook scripts verify the server with an HMAC challenge before trusting an answer.

## Sealed hooks and deny rules

See [Why sealed copies](CLAUDE-CODE.md#why-sealed-copies). Nothing edits `~/.claude/settings.json`.

## Vitrin

History is a SQLite database with image files beside it, stored in the app container (`~/Library/Containers/dev.nubrix.app/Data/Library/Application Support/Nubrix/Vitrin`) with 0600/0700 permissions. It is not encrypted yet. The Vitrin panel is hidden from screen sharing and recording by default (Settings, Vitrin). The secret guard is a heuristic: it reduces the chance of storing a credential but cannot catch everything; use excluded apps and the capture toggles, and clear the history from Settings, Vitrin when needed.

## GitHub token

Kept in the macOS Keychain only and sent only to `api.github.com`. Nubrix only sends read requests; Settings asks you to create the token read-only and limited to the repositories you choose, which GitHub then enforces.

## Mirror

Mirror uses the camera only for a live preview layer in the notch panel. There is no video or photo output, so no frame is recorded, saved or sent. The camera starts when the panel opens and stops when it closes. Nubrix asks for camera access only when you click "Turn On Camera" in the Mirror panel, never at launch or in onboarding.

## Notifications from other apps

Off by default. When on, `NubrixHelper` opens the macOS notification database (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`) read-only every 2 seconds, and only when the file has changed. Notifications of apps you did not tick never leave the helper. The app keeps the rest in memory only (the Notifications tab holds the last 50 notifications, stacked by chat): nothing is written to disk or logged, and notifications from before you turned the feature on, or from before a restart, are not shown. Full Disk Access lets Nubrix read more than this one file; turn it off in System Settings, Privacy & Security, Full Disk Access when you stop using the feature. The database format is undocumented, so a macOS update can break the feature; Settings then shows "Not supported on this macOS version".

## Unread counts (Dock badges)

Off by default ("Show unread counts"). When on, the sandboxed app reads the badge text of each ticked app (the number on its Dock icon) from LaunchServices every 3 seconds, only while at least one ticked app is running, and not while the Mac is asleep or locked. Only the badge text is read and it is kept in memory only; it is not added to the inbox, written to disk or logged. While the Other apps settings are open, Nubrix lists the running apps so you can tick them. No permission or entitlement is needed. The reading uses private LaunchServices functions (`_LSASNCreateWithPid`, `_LSCopyApplicationInformationItem`, the same ones `lsappinfo` uses), looked up at run time; if a macOS update removes them, the feature turns itself off and Settings says so instead of crashing.

## Signing

From 0.1.1 on, GitHub Actions builds each release without access to any signing key, then a separate job, which only `v*` tags can start, signs every piece of code with a Developer ID, notarizes the app with Apple and staples the ticket (see [CONTRIBUTING.md](../../CONTRIBUTING.md#signing-and-notarization)). 0.1.0 was ad-hoc signed and not notarized. All releases use the hardened runtime without `get-task-allow`. The app carries `disable-library-validation` so that `/usr/bin/perl` can load the bundled MediaRemote adapter. See [SUPPLY-CHAIN.md](SUPPLY-CHAIN.md) and [AUDIT-2026-10-31-release.md](AUDIT-2026-10-31-release.md) for the audit and known limits.

## Reporting a problem

See [SECURITY.md](../../SECURITY.md) for how to report a vulnerability privately.
