# Privacy and security

How Nubrix keeps your data on your Mac and limits what each part can do. For a summary, see the [README](../../README.md#privacy-and-security). To report a problem, see [SECURITY.md](../../SECURITY.md).

## Local only

Everything stays on your Mac. Nubrix has no analytics, no account and sends nothing to a Nubrix server. Automatic updates through Sparkle are on by default; turn them off in Settings, About, Updates, and Nubrix then makes no update request and installs nothing unless you press Check Now.

## Network use

The complete list:

- `api.github.com`, only if you add a fine-grained read-only token (off until then; see [GitHub integration](../../README.md#github-integration)). The token goes nowhere else.
- `github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml` (GitHub redirects to `release-assets.githubusercontent.com`), once a day while automatic checks are on (the default) or when you press Check Now. Sparkle sends a plain GET with `User-Agent: Nubrix/<version> Sparkle/<version>`, no GitHub token, no cookies and no system profile (`SUEnableSystemProfiling` is off). The feed must carry a valid EdDSA signature (`SURequireSignedFeed`). When an update is installed (automatically by default, or after you confirm it), Sparkle downloads `Nubrix-X.Y.Z.zip` from the same release, checks its EdDSA signature before unpacking (`SUVerifyUpdateBeforeExtraction`) and checks that the new app is signed with the same Developer ID. Only Developer ID release builds do any of this; source and Debug builds never start the updater. Stored on your Mac (app container defaults): `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SULastCheckTime` and Sparkle's skipped-version state.
- `lrclib.net` receives the track title and artist when lyrics are turned on (off by default).
- LottieFiles: a visualizer animation (JSON) is downloaded when the built-in music visualizer is turned off in Settings.
- Artwork URLs supplied by Spotify or YouTube Music are fetched to show the cover.
- `localhost:26538`, the local API of the YouTube Music desktop app, when that controller is used.
- The `claude` command-line tool, run by the helper to read your plan usage (see [Usage, context and cost](CLAUDE-CODE.md#usage-context-and-cost)); Claude itself talks to Anthropic as it always does. Turn it off in Settings, Claude Code.

## Permissions

Nubrix asks for nothing at launch. Each permission is asked the first time you use the feature that needs it, and Settings, Permissions shows the state of all of them. That tab reads the status without asking, so opening it never shows a system dialog. Automation for Music or Spotify is asked when that source is used: after you choose it, or when Now Playing does not work on your Mac and Nubrix falls back to Spotify (if installed) or Apple Music. Bluetooth is asked once setup is done, when "Device and Mac alerts" is on (the default), to read the battery of AirPods and other Bluetooth devices. Accessibility and Full Disk Access are recorded by macOS under "Nubrix". Version 0.1.1 and earlier asked for camera, calendar, Accessibility and Full Disk Access up front in onboarding; 0.1.2 fixed this. Details are in [PERMISSIONS-AND-SETTINGS.md](PERMISSIONS-AND-SETTINGS.md).

## Sandbox and helper split

The app is sandboxed. The only unsandboxed part is the small XPC service `NubrixHelper`, used for Accessibility-based key handling (the Accessibility grant is recorded under "Nubrix", not the helper), brightness, the `claude /usage` probe and, when turned on, the read-only reader of the macOS notification database. The app can read `~/.config/nubrix/` (the sealed hook scripts) but cannot write there, so it cannot change what Claude Code runs; its only writable config location is `~/.config/nubrix-run/`.

The app has one mach-lookup temporary exception (`dev.nubrix.app-spks` and `-spki`) so it can talk to Sparkle's installer. That installer (`Installer.xpc`, which starts `Autoupdate` and `Updater.app`) runs outside the sandbox only to replace the app bundle after you accept an update. Sparkle's Downloader service is removed from the bundle, because Nubrix has the network client entitlement and downloads itself. `NubrixHelper` no longer has the `isHomebrewInstall` method.

The entitlements allow Apple Events only to Spotify, Music, Terminal, iTerm and Ghostty. To find a Claude session's tab, the scripts get only a checked terminal device name (`/dev/ttysNNN`) and, for Ghostty, the session folder passed as a script parameter, never as script text. A Warp session link from the hook is opened only in the exact `warp…://session/<32 hex>` form and only when the app that handles it is a `dev.warp.*` app.

## Local endpoint

The event server binds to the loopback interface only (127.0.0.1) on a random port, authenticates on request headers with a random bearer token and caps connections. Port, token and process id are written to `~/.config/nubrix-run/agent-endpoint` (file 0600 in a 0700 directory). Hook scripts verify the server with an HMAC challenge before trusting an answer.

## Sealed hooks and deny rules

See [Why sealed copies](CLAUDE-CODE.md#why-sealed-copies). Nothing edits `~/.claude/settings.json`.

## Vitrin

History is a SQLite database with image files beside it, stored in the app container (`~/Library/Containers/dev.nubrix.app/Data/Library/Application Support/Nubrix/Vitrin`) with 0600/0700 permissions and excluded from backup. Debug builds use a separate `Vitrin-Debug` folder with a key file, so they never read or change the release history or its keychain item. The Vitrin panel is hidden from screen sharing and recording by default (Settings, Vitrin). The secret guard is a heuristic: it reduces the chance of storing a credential but cannot catch everything; use excluded apps and the capture toggles, and clear the history from Settings, Vitrin when needed.

### Encryption

History is encrypted at rest and there is no switch to turn it off.

- Encrypted: the text content, the previews, the source app, and the image files and their thumbnails. The cipher is AES-GCM with a 256-bit key.
- Duplicate detection uses a keyed HMAC instead of a plain hash, so the database cannot be used to confirm a guess about what you copied.
- The key is a generic password item named "Nubrix Vitrin history key" in your login keychain. It does not sync through iCloud.

### What is not encrypted

- Item kind, sizes, timestamps, pin state and the number of items.
- Copies made when you drag an item out: the receiving app needs a readable file, so it is written to a temporary folder and removed after 5 minutes.
- The system pasteboard itself.
- Screenshot originals in your own screenshot folder.
- The running app's memory. Search works on an index that exists only in memory while you search; it is dropped when the panel closes, after a short idle time and when the screen locks.

### What it protects against

- Copies of the Vitrin folder, including backup or sync tools that ignore the backup exclusion.
- Processes that can read the app container but cannot get the key without a keychain prompt.

It does not protect against someone using your logged-in Mac while it is unlocked, a tool you clicked "Always Allow" for in the keychain prompt, or the running app. FileVault protects the disk while the Mac is off.

### Keychain prompts

- Updating from one Developer ID release to the next never asks.
- Switching between a build you made yourself (signed with an Apple Development certificate) and a Developer ID release makes macOS ask once per direction. "Always Allow" ends it.
- If you click Deny, Vitrin stays locked: nothing is captured or shown, but nothing is deleted either. Settings, Vitrin shows Retry. See [Vitrin says it is locked](TROUBLESHOOTING.md#vitrin-says-it-is-locked).
- If the key is gone from the keychain, the history cannot be read, so it is reset and Vitrin says so once. See [Vitrin history was reset](TROUBLESHOOTING.md#vitrin-history-was-reset).

### Reset

"Reset history and key" in Settings, Vitrin deletes everything, including pinned items, and creates a new key. Remnants of earlier data that may still be on the disk become unreadable without the old key.

### Upgrading from an unencrypted version

On the first start after the upgrade, existing history is encrypted in place and the old unencrypted copies, including the old search index, are deleted. This cannot reach every copy on the storage device: SQLite's write-ahead log, APFS copy-on-write and SSD wear levelling can leave remnants until the space is overwritten. FileVault protects them while the Mac is off. "Reset history and key" makes them unreadable.

On macOS 15.4 and later Vitrin respects "Paste from Other Apps": with "Ask" it does not read copied items in the background and waits for you to click "Save Copied Item"; with "Deny" it saves nothing.

## GitHub token

Kept in the macOS Keychain only and sent only to `api.github.com`. Nubrix only sends read requests; Settings asks you to create the token read-only and limited to the repositories you choose, which GitHub then enforces.

## Mirror

Mirror uses the camera only for a live preview layer in the notch panel. There is no video or photo output, so no frame is recorded, saved or sent. The camera starts when the panel opens and stops when it closes. Nubrix asks for camera access only when you click "Turn On Camera" in the Mirror panel, never at launch or in onboarding.

## Device batteries and everyday alerts

These run on your Mac only. Nothing is written to disk, logged or sent anywhere, and each one has its own switch in Settings, Everyday. While a switch is off, that part reads nothing.

- **Device batteries.** Nubrix reads the battery level of connected Bluetooth devices: AirPods and Beats through IOBluetooth (the left, right and case levels are private properties, read only after checking they exist), and Magic Mouse, Keyboard and Trackpad from the IOKit registry (`BatteryPercent`). It reads again a few seconds after a device connects and then once a minute while one is connected. Needs the Bluetooth permission and the `com.apple.security.device.bluetooth` entitlement.
- **Sound output.** Listens for changes of the default output device in Core Audio and reads the new device's name. No permission.
- **Drives.** Uses the system's mount and unmount notifications and reads the volume name and free space of external drives and memory cards. Eject calls macOS's own eject; if the sandbox does not allow it, Nubrix opens the drive in Finder instead. No permission.
- **Microphone and camera.** Reads only whether the microphone or a camera is in use (Core Audio and Core Media IO "running somewhere" flags). On macOS 14.2 and later it also reads which app is using the microphone. Nubrix never opens the microphone or camera for this and records nothing. No permission. Nubrix's own Mirror is ignored.
- **Internet.** `NWPathMonitor` reports whether the Mac has a network path. Nubrix sends no request to check this.

## Notifications from other apps

Off by default. When on, `NubrixHelper` opens the macOS notification database (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`) read-only every 2 seconds, and only when the file has changed. Notifications of apps you did not tick never leave the helper. The app keeps the rest in memory only (the Notifications tab holds the last 50 notifications, grouped by chat, by app or not at all, as set in Settings): nothing is written to disk or logged, and notifications from before you turned the feature on, or from before a restart, are not shown. Full Disk Access is granted to Nubrix (the helper does not appear separately) and lets it read more than this one file; turn it off in System Settings, Privacy & Security, Full Disk Access when you stop using the feature. The database format is undocumented, so a macOS update can break the feature; Settings then shows "Not supported on this macOS version".

## Unread counts (Dock badges)

Off by default ("Show unread counts"). When on, the sandboxed app reads the badge text of each ticked app (the number on its Dock icon) from LaunchServices every 3 seconds, only while at least one ticked app is running, and not while the Mac is asleep or locked. Only the badge text is read and it is kept in memory only; it is not added to the inbox, written to disk or logged. While the Other apps settings are open, Nubrix lists the running apps so you can tick them. No permission or entitlement is needed. The reading uses private LaunchServices functions (`_LSASNCreateWithPid`, `_LSCopyApplicationInformationItem`, the same ones `lsappinfo` uses), looked up at run time; if a macOS update removes them, the feature turns itself off and Settings says so instead of crashing.

## Signing

From 0.1.1 on, GitHub Actions builds each release without access to any signing key, then a separate job, which only `v*` tags can start, signs every piece of code with a Developer ID, notarizes the app with Apple and staples the ticket (see [CONTRIBUTING.md](../../CONTRIBUTING.md#signing-and-notarization)). 0.1.0 was ad-hoc signed and not notarized. Release bundles contain nine Mach-O files; the four from Sparkle (`Sparkle`, `Autoupdate`, `Updater`, `Installer`) are re-signed with the Developer ID and carry no entitlements. The update feed is signed by a separate job with an EdDSA key that never shares a job with the Developer ID certificate or the notary key. All releases use the hardened runtime without `get-task-allow`. The app carries `disable-library-validation` so that `/usr/bin/perl` can load the bundled MediaRemote adapter. See [SUPPLY-CHAIN.md](SUPPLY-CHAIN.md) and [AUDIT-2026-10-31-release.md](AUDIT-2026-10-31-release.md) for the audit and known limits.

## Reporting a problem

See [SECURITY.md](../../SECURITY.md) for how to report a vulnerability privately.
