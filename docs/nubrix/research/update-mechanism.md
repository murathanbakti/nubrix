# Research: an update mechanism for Nubrix

Status: research note, 2026-11-03. No code changed. Decision requested: see [Recommendation](#recommendation).

## Where we are

- Sparkle was disabled in `81879ee` (feed URL and `SUPublicEDKey` removed) and deleted in `d26f2d5` (package, `Nubrix/components/Settings/SoftwareUpdater.swift`, `SU*` Info.plist keys, update UI). `docs/nubrix/ROADMAP.md` lists "An update mechanism" under Phase 5 Remaining.
- Users are told to update by hand: README "Updating" (`brew upgrade --cask nubrix`, re-run `install.sh`, or `git pull && scripts/install-local.sh`), then re-run `install-hooks.sh` so the sealed copies in `~/.config/nubrix/bin/` match.
- Release pipeline: `.github/workflows/release.yml` builds without secrets (`build` job), then the `release` job (environment `release`) signs every Mach-O with Developer ID + hardened runtime (`scripts/sign-release.sh`), notarizes and staples (`scripts/notarize-release.sh`), zips (`scripts/package-release.sh`), writes `Nubrix-X.Y.Z.zip.sha256` and the cask (`scripts/render-cask.sh` from `packaging/homebrew/nubrix.rb.template`), and creates a **draft** GitHub release. A human publishes it and copies the cask into `murathanbakti/homebrew-tap`.
- `scripts/verify-bundle.sh` allows exactly 5 Mach-O files, `XPCServices` = `NubrixHelper.xpc`, `Frameworks` = `Lottie.framework MediaRemoteAdapter.framework`.
- `scripts/install.sh` already implements a safe install: HTTPS-only curl, `releases/latest`, SHA-256 file, bundle id + version match, `codesign -R 'anchor apple generic and certificate leaf[subject.OU] = "399MAAJ7QT"'`, `spctl` must say `source=Notarized Developer ID`, atomic swap with rollback.
- App is sandboxed and already has `com.apple.security.network.client` (`Nubrix/Nubrix.entitlements`, `Nubrix/Nubrix.release.entitlements`). `NubrixHelper` is an unsandboxed XPC service that only accepts `dev.nubrix.app` signed by its own team (`NubrixHelper/main.swift`, `clientRequirement`).
- `docs/nubrix/PRIVACY-AND-SECURITY.md` promises "no auto-updater" and lists every network destination; any checker must be added there.
- Cask has `livecheck strategy :github_latest` and **no** `auto_updates`.

## Option A: Sparkle 2

Current: Sparkle 2.10.1 (25 Oct 2026), macOS 12+; 2.9.6 shipped security fixes ([releases](https://github.com/sparkle-project/Sparkle/releases)).

What a sandboxed setup needs ([sandboxing](https://sparkle-project.org/documentation/sandboxing/)):
- Info.plist: `SUEnableInstallerLauncherService = YES`. No `SUEnableDownloaderService`, because the app already has `network.client`.
- Entitlements (both files): `com.apple.security.temporary-exception.mach-lookup.global-name` = `dev.nubrix.app-spks`, `dev.nubrix.app-spki`. That's one more temporary exception.
- Security keys ([customization](https://sparkle-project.org/documentation/customization/)): `SUPublicEDKey`, `SUVerifyUpdateBeforeExtraction = YES` (2.7.3+) and `SURequireSignedFeed = YES` (2.9+, signs the appcast and release notes, not just the archive). Sparkle requires the Apple signature and the EdDSA signature to match, so the Developer ID and the EdDSA key can't both rotate in one update ([docs](https://sparkle-project.org/documentation/)).
- Menu-bar app: implement `supportsGentleScheduledUpdateReminders` (2.2+) ([gentle reminders](https://sparkle-project.org/documentation/gentle-reminders/)). `SUScheduledCheckInterval` defaults to 1 day. When `SUEnableAutomaticChecks` is unset, Sparkle asks on second launch. `SUEnableSystemProfiling` must stay NO.
- Channels: `<sparkle:channel>` plus the `allowedChannels` delegate; phased rollout through `sparkle:phasedRolloutInterval` ([publishing](https://sparkle-project.org/documentation/publishing/)).

Repo impact:
- `Nubrix.xcodeproj/project.pbxproj` + `Package.resolved`: add the Sparkle SwiftPM package; `THIRD_PARTY_LICENSES`, `NOTICE` (MIT); `docs/nubrix/SUPPLY-CHAIN.md`.
- `scripts/verify-bundle.sh`: `expected_frameworks` gains `Sparkle.framework`. `expected_macho` grows from 5 to about 9 or 10: `Sparkle.framework/Versions/B/{Sparkle,Autoupdate}`, `Updater.app/Contents/MacOS/Updater`, `XPCServices/Installer.xpc/...` and, unless stripped in a build phase, `Downloader.xpc/...`.
- `scripts/sign-release.sh`: today it signs each `*.framework` as one unit. Sparkle must be signed inside-out (Installer.xpc, Downloader.xpc, Autoupdate, Updater.app, framework), never with `--deep`, and with `--preserve-metadata=entitlements` on Downloader.
- `scripts/package-release.sh` `check_app`: the arch loop hard-codes `Versions/A`; Sparkle uses `Versions/B`.
- `release.yml`: new secret `SPARKLE_ED_PRIVATE_KEY` in the `release` environment, and `generate_appcast` / `sign_update` after notarization. The appcast must not point at a **draft** release. That takes a second workflow on `release: published` that signs and uploads `appcast.xml` (to Pages, or as a release asset behind `releases/latest/download/appcast.xml`), or manual appcast publishing.
- Cask: add `auto_updates true`. Plain `brew upgrade` then skips Nubrix and only `--greedy`/`--greedy-auto-updates` (or `HOMEBREW_UPGRADE_GREEDY`) upgrades it ([manpage](https://docs.brew.sh/Manpage)), so brew's recorded version drifts.
- Sparkle's update replaces the bundle but does not refresh the sealed hook copies, so the post-update "re-run install-hooks" reminder is still needed.

Assessment: Sparkle is the safest *installer* available, but it reverses a deliberate decision. It adds about 5 Mach-O files from a third party, a mach-lookup exception, a second signing key and a second publish workflow to a project whose supply-chain story rests on a short, allowlisted bundle. For an app with a small user base that ships every few weeks, this cost buys one-click installs.

## Option B: in-house checker

### B1: notify only (recommended v1)

- Once a day (an `NSBackgroundActivityScheduler` with interval 86400, tolerant of sleep), plus "Check now", the sandboxed app sends `GET https://api.github.com/repos/murathanbakti/nubrix/releases/latest` from an ephemeral `URLSession` with no cookies or cache, no auth header (never the user's GitHub token) and redirects refused, like `GitHubClient`. `releases/latest` excludes drafts and prereleases ([REST docs](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)), so only releases you published count. The unauthenticated limit is 60 requests an hour per IP ([rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)); a 304 only saves quota when authenticated ([best practices](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api)), so skip ETags and stick to once a day.
- Parse only `tag_name` and require it to match `^v\d+\.\d+\.\d+$`. Compare it numerically with `CFBundleShortVersionString` and show an update only if it is **strictly greater**; that is the downgrade protection. Never use URLs or markdown from the response. The "View release" button opens a URL built locally: `https://github.com/murathanbakti/nubrix/releases/tag/v<validated>`.
- Why no feed signature: B1 runs, downloads and installs nothing. A forged or MITM'd response (TLS to `api.github.com` already guards against this) can at worst show a false "update available" that opens your own repo's releases page. Installing still goes through brew or `install.sh`, which check Team ID and notarization.
- The UI tells each install type what to do:
  - **Homebrew**: tell the user to run `brew upgrade --cask nubrix`, with a copy button, and never touch the bundle. Detect it with a new read-only helper method, because the sandbox can't see `/opt/homebrew`: it checks `/opt/homebrew/Caskroom/nubrix` and `/usr/local/Caskroom/nubrix` (a heuristic; brew has no official API for this) and returns only a bool.
  - **Release zip / `install.sh`**: "View release", plus the `install.sh` one-liner from the README.
  - **Source build**: get the app's own Team ID (same `SecCodeCopySelf` code as `ownTeamIdentifier()` in `NubrixHelper/main.swift`). If it isn't `399MAAJ7QT`, show "built from source: `git pull && scripts/install-local.sh`", or turn the checker off.
  - Every banner reminds the user to re-run `install-hooks.sh` after updating.
- Cask: leave `auto_updates` out. Homebrew says not to use it when the menu item only opens a webpage ([Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)), so brew stays the single source of truth and nothing fights.
- Settings: an "Updates" section in `About`: version, a toggle to check once a day, "Check now", last checked / status, and "Skip this version". No channel picker in v1: `release.yml` accepts only `vX.Y.Z` tags, so there is no beta stream yet. A later beta channel would read `/releases?per_page=10`, filter `prerelease`, and allow `vX.Y.Z-beta.N` tags.
- Privacy: the request carries only the IP and a fixed `User-Agent: Nubrix/<version>`: no identifiers, no telemetry, nothing stored except last-check date and latest/skipped version in Defaults. The automatic check stays **off until the user opts in**, which keeps the README/PRIVACY promise. Ask once, in the About "Updates" section and in the menu bar, in the spirit of Sparkle's second-launch prompt. "Check now" always works.
- CI: none required. Optionally, add a step to the `release` job that fails if `$TAG` is not greater than the current `releases/latest` tag, to keep version ordering monotonic.

### B2: download, verify, swap via the helper (not recommended)

This would add an XPC method that downloads the zip, checks the SHA-256, bundle id, version > current, `codesign -R` Team ID requirement and `spctl` "Notarized Developer ID", then swaps the bundle atomically (`install.sh`'s logic in Swift) and relaunches. The problems:
- It turns the unsandboxed helper, which already holds Accessibility and Full Disk Access, into a privileged code-writer.
- It reimplements Sparkle's installer without Sparkle's years of review: TOCTOU between verify and move, symlinks in the zip, writable `/Applications` only for admins, and the helper running from the bundle it replaces.
- It still needs the `auto_updates` / brew coordination.

If one-click install becomes a real need, use Sparkle (A), not B2.

## Security checklist (applies to any option)

- HTTPS only, fixed host, no redirects followed by the checker; no auth token sent.
- Install only versions strictly newer than the running one; validate the version format before use.
- Never execute or open anything from the network without Developer ID Team `399MAAJ7QT` + notarization checks (B1 never does; brew/`install.sh` do).
- Do not render remote release notes in-app (avoid a WebView/markdown surface).
- No telemetry, no identifiers; document the new destination in `PRIVACY-AND-SECURITY.md#network-use`.

## Recommendation

**B1, the notify-only checker, for v1.** It costs about 200 lines of Swift and one tiny read-only helper method, makes no change to the bundle, entitlements, verify-bundle allowlist, signing or CI, and doesn't fight Homebrew. If users later ask for one-click installs, move to **Sparkle 2** (A) with `SUVerifyUpdateBeforeExtraction` + `SURequireSignedFeed`, a `release: published` appcast workflow and `auto_updates true` in the cask, and accept the allowlist growth. Skip B2.

### Files B1 would touch

| File | Change |
|---|---|
| `Nubrix/Features/Updates/UpdateChecker.swift` (new) | Actor: fetch `releases/latest`, validate `tag_name`, semver compare, scheduler, published state |
| `Nubrix/Features/Updates/UpdateDefaults.swift` (new) | `Defaults.Keys`: `updateAutoCheck: Bool?` (nil = not asked), `updateLastCheck: Date?`, `updateLatestVersion: String?`, `updateSkippedVersion: String?` |
| `Nubrix/components/Settings/SettingsView.swift` | `struct About`: "Updates" section (toggle, Check now, status, per-install instructions) |
| `Nubrix/NubrixApp.swift` | `MenuBarExtra`: "Update available: X.Y.Z…" item; start the scheduler in `AppDelegate` |
| `NubrixHelper/NubrixHelperProtocol.swift`, `NubrixHelper/NubrixHelper.swift`, `Nubrix/XPCHelperClient/XPCHelperClient.swift` | `isHomebrewInstall(with reply: (Bool) -> Void)`: `FileManager.fileExists` on the two Caskroom paths |
| `Nubrix/Localizable.xcstrings` | New strings |
| `NubrixTests/` | Version parse/compare and tag validation tests |
| `README.md` (Updating, Privacy), `docs/nubrix/PRIVACY-AND-SECURITY.md`, `docs/nubrix/INSTALL.md`, `docs/nubrix/ROADMAP.md` | Document the opt-in check and `api.github.com` use without a token |
| `.github/workflows/release.yml` (optional) | Monotonic-version check against `releases/latest` |

Unchanged: `scripts/verify-bundle.sh`, `scripts/sign-release.sh`, `scripts/package-release.sh`, entitlements, `packaging/homebrew/nubrix.rb.template`.

## Sources

- Sparkle sandboxing: https://sparkle-project.org/documentation/sandboxing/
- Sparkle settings: https://sparkle-project.org/documentation/customization/
- Sparkle publishing: https://sparkle-project.org/documentation/publishing/
- Sparkle basic setup / key rotation: https://sparkle-project.org/documentation/
- Sparkle gentle reminders: https://sparkle-project.org/documentation/gentle-reminders/
- Sparkle releases: https://github.com/sparkle-project/Sparkle/releases
- Homebrew Cask Cookbook (`auto_updates`): https://docs.brew.sh/Cask-Cookbook
- Homebrew manpage (`--greedy`, `--greedy-auto-updates`): https://docs.brew.sh/Manpage
- Homebrew on Sparkle casks lacking `auto_updates`: https://github.com/Homebrew/homebrew-cask/issues/170994
- GitHub latest release: https://docs.github.com/en/rest/releases/releases#get-the-latest-release
- GitHub rate limits: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api
- GitHub conditional requests: https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api
