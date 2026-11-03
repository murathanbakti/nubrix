# Changelog

All notable changes to Nubrix. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Opt-in automatic updates with Sparkle 2.10.1 in Settings, About, Updates: check automatically, install automatically, Check Now and the last check time. Nothing is checked or installed until you turn it on. Only Developer ID releases update themselves.
- Gentle reminders for a pending update in the menu bar and the notch inbox, and a reminder when the installed Claude Code hook scripts differ from the app's.

### Changed

- Simplified Settings: a grouped sidebar, a Claude Code tab, Meetings in Calendar, Battery in General, and Mirror, accent and window appearance in Appearance. Dead and placeholder settings were removed.
- Sparkle replaces the notify-only update check. Source and Debug builds never update themselves.

### Removed

- The GitHub-API update checker (`api.github.com` release check) and the helper's Homebrew probe.

### Security

- Signed appcast (`SURequireSignedFeed`), EdDSA verification before extraction and a Developer ID match for every update. One new mach-lookup temporary exception for Sparkle's installer, four new Mach-O files from Sparkle and Sparkle's Downloader service removed from the bundle.

## [0.1.2] - 2026-11-03

### Added

- Click a Claude Code session in Ghostty or Warp and its own tab comes to the front. Ghostty 1.4 or later is matched by terminal device, Ghostty 1.3 by working directory when only one tab has it, and Warp (recent builds) through the link Warp sets for the session, with no permission.
- Opt-in, notify-only update check in Settings, About, Updates, with Check now, Skip this version and an item in the menu bar. It shows the update command for Homebrew, the install script or a source build. Nothing is downloaded or installed.
- Unread counts without Full Disk Access ("Show unread counts", off by default). Nubrix reads the Dock badge number of the running apps you tick.
- Settings, Permissions tab with live status for Accessibility, Full Disk Access, Camera, Calendar, Automation and Paste from Other Apps, and a Grant button for each. Opening it never shows a system dialog.
- Vitrin shows its encryption status, with Retry when the keychain denied access and "Reset history and key".
- Open the exact Claude session from the notch: the Claude desktop app, or the Terminal or iTerm tab.
- Settings, Tabs: reorder the notch tabs and hide the ones you don't use. Every feature that needs a permission or controls another app has its own switch.
- Unit tests (`NubrixTests`), `scripts/run-tests.sh` and a test job in CI.

### Changed

- Nothing is asked at launch. Each permission is asked the first time you use the feature that needs it, and onboarding only lists which features will ask. Camera access is asked when you first open Mirror.
- Nubrix no longer selects Apple Music by itself when Now Playing is unavailable. It asks once which music source to use, and Automation for Music or Spotify is asked after that choice.
- Full Disk Access: "Quit & Reopen" brings you back to where you started with an "Access granted" panel.
- Vitrin history is encrypted at rest with AES-GCM. Search runs on an index in memory and matches substrings, and the SQLite FTS5 index is gone. The key is a keychain item named "Nubrix Vitrin history key"; macOS may ask once to allow access.
- Existing history is encrypted in place on the first start after the update, and the old unencrypted copies are deleted.
- Notifications from the same chat are stacked into one card with the newest message and "+N more".
- New app icon and logo.
- Debug builds and the test host use the bundle id `dev.nubrix.app.debug` and show as "Nubrix Debug", with their own container, preferences and Vitrin folder. `scripts/install-local.sh` signs with a team-based designated requirement, so a grant made by a local build survives a release of the same team.
- Accessibility and Full Disk Access are listed under "Nubrix" in the docs, not under the helper.
- README: quick start, update notes and a CI badge.

### Fixed

- Onboarding no longer restarts when you use "Quit & Reopen" during it.
- Vitrin respects the macOS setting Paste from Other Apps (macOS 15.4 and later). With Ask it shows a "Save Copied Item" pill instead of reading in the background, and with Deny it saves nothing.
- A Debug build no longer reads, prompts for or changes the installed app's Vitrin history and keychain item.
- `install.sh` no longer fails after installing when it reads the signature.
- Scrolling a list no longer starts the notch close gesture.
- Fewer wakeups and redraws while idle.

### Security

- Vitrin history is encrypted at rest. Duplicate detection uses a keyed HMAC, so the database cannot confirm a guess about what you copied. Encryption does not reach every old plaintext copy on an SSD; "Reset history and key" makes remnants unreadable. See [Privacy and security](docs/nubrix/PRIVACY-AND-SECURITY.md#encryption).
- The update check sends no token or cookies, refuses redirects and reads only the release's version number.
- Tab jump passes the terminal device and session folder to AppleScript as parameters, never as script text. A Warp link is opened only in its exact form and only when a Warp app handles it.
- Dock badge counts use private LaunchServices functions looked up at run time. If macOS removes them, the feature turns itself off. Badge text stays in memory. See [Privacy and security](docs/nubrix/PRIVACY-AND-SECURITY.md#unread-counts-dock-badges).
- Hardened the helper's XPC interface and the hook scripts.

## [0.1.1] - 2026-11-02

The first release signed with a Developer ID and notarized by Apple. It opens without a Gatekeeper warning.

### Added

- Developer ID signing and notarization in the release workflow. The build runs without any secret, and a separate job that only `v*` tags can start signs and notarizes the app.
- Notifications from other apps: banners on the closed notch and a Notifications tab with the last 50. It is off by default and needs Full Disk Access, with a short guide for granting it.
- `scripts/setup-release-signing.sh`, which sets up the signing secrets.

### Changed

- The Homebrew cask no longer removes the quarantine flag, and `install.sh` checks the Team ID and notarization of every release after 0.1.0.
- `scripts/install-local.sh` signs with your own Apple Development certificate when one exists, so macOS keeps Keychain access and permissions across rebuilds.
- Release binaries are stripped, and the debug symbols are kept as a workflow artifact.
- The MediaRemote adapter is rebuilt for macOS 14 from a pinned upstream tag.
- Nubrix quits cleanly on SIGTERM and stops the now-playing helper process.
- README images are rendered mockups with sample data.

### Fixed

- Calendar: Nubrix no longer asks for Reminders access, and the calendar selection is honored.
- A crash in onboarding that came from the Reminders request.
- Installing and release fixes found in QA, such as an app left missing when an install failed halfway. See the [QA report](docs/nubrix/QA-2026-11-02-v0.1.1.md).

### Security

- `verify-bundle.sh` allows exactly the expected code files in the release bundle before anything is signed.
- The release workflow gives `GH_TOKEN` only to the release step and rejects partial signing secrets.

## [0.1.0] - 2026-11-01

The first public release. Ad-hoc signed and not notarized, so macOS asks you to approve it the first time ([First launch and Gatekeeper](README.md#first-launch-and-gatekeeper)).

### Added

- Claude Code sessions in the notch: status, project, git branch, where each one runs, context bar, token count and plan usage.
- Permission requests from Claude Code with Allow and Deny in the notch, and a second click for risky commands.
- Sealed hook scripts, installed as read-only copies outside any repository, and a status-only plugin.
- Vitrin, a clipboard and screenshot history with developer insights and a guard against storing credentials.
- `notchctl`, the Dev tab with localhost ports, and the GitHub integration with a fine-grained read-only token.
- Calendar sheet, meeting countdown and Mirror.
- Now playing, HUDs and a file shelf, inherited from boring.notch.
- Install script, Homebrew cask and releases built by GitHub Actions.

### Security

- The app runs in the macOS sandbox. The event server listens on loopback only with a random token, and the hooks verify Nubrix with an HMAC challenge.
- The auto-updater from the upstream project was removed.

[0.1.2]: https://github.com/murathanbakti/nubrix/releases/tag/v0.1.2
[0.1.1]: https://github.com/murathanbakti/nubrix/releases/tag/v0.1.1
[0.1.0]: https://github.com/murathanbakti/nubrix/releases/tag/v0.1.0
