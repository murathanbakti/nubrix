# Plan: notify-only update check

Status: superseded by [sparkle-auto-update.md](sparkle-auto-update.md). Original status: plan, 2026-11-03. Decision: option B1 from [research/update-mechanism.md](../research/update-mechanism.md). Nubrix only *tells* the user that a newer release exists and how to install it. It downloads, runs and replaces nothing.

Out of scope: Sparkle, download-and-swap, signing, entitlements, `verify-bundle.sh`, the cask, `release.yml`, `Localizable.xcstrings` (new strings fall back to their English keys; translating them is a later pass, and keeping the catalog untouched avoids merge conflicts with the parallel branches).

## Files

| File | Contents |
|---|---|
| `Nubrix/Features/Updates/ReleaseVersion.swift` (new) | `struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible` (`major`, `minor`, `patch`); `init?(tag:)`, `init?(bundleVersion:)`, `tag` (`"v1.2.3"`), `description` (`"1.2.3"`) |
| `Nubrix/Features/Updates/UpdateParsing.swift` (new) | `enum UpdateParsing`: `latestVersion(from: Data) throws -> ReleaseVersion` (throws `UpdateFailure`); `enum UpdateDecision`: `evaluate(latest:current:skipped:) -> UpdateVerdict`; `enum UpdateSchedule`: `isDue(...)` |
| `Nubrix/Features/Updates/UpdateInstallKind.swift` (new) | `enum UpdateInstallKind { homebrew, releaseZip, sourceBuild }`, `resolve(teamIdentifier:isHomebrew:)`, `struct UpdateInstructions`, `instructions(for:)`, `UpdateLinks.releaseURL(for:)`, `AppSigningIdentity.teamIdentifier()` |
| `Nubrix/Features/Updates/UpdateClient.swift` (new) | `actor UpdateClient`: one GET, no redirects |
| `Nubrix/Features/Updates/UpdateDefaults.swift` (new) | Defaults keys |
| `Nubrix/Features/Updates/UpdateStore.swift` (new) | `@MainActor final class UpdateStore: ObservableObject`, scheduling and state |
| `Nubrix/Features/Updates/UpdateViews.swift` (new) | `UpdatesSettingsSection` (About), `UpdateMenuItems` (menu bar) |
| `Nubrix/components/Settings/SettingsView.swift` | `About`: insert `UpdatesSettingsSection()` after "Version info" |
| `Nubrix/NubrixApp.swift` | `MenuBarExtra`: `UpdateMenuItems()` above Settings; `applicationDidFinishLaunching`: `UpdateStore.shared.start()`; `applicationWillTerminate`: `UpdateStore.shared.stop()` |
| `NubrixHelper/NubrixHelperProtocol.swift`, `NubrixHelper/NubrixHelper.swift` | `isHomebrewInstall(with:)` |
| `Nubrix/XPCHelperClient/XPCHelperClient.swift` | `nonisolated func isHomebrewInstall() async -> Bool` (false on any XPC error) |
| `NubrixTests/Updates/*.swift` (new) | Unit tests, see below |
| `README.md`, `docs/nubrix/PRIVACY-AND-SECURITY.md`, `docs/nubrix/ROADMAP.md` | Document the opt-in check |

## Helper XPC change

```swift
func isHomebrewInstall(with reply: @escaping (Bool) -> Void)
```

Implementation: `reply(["/opt/homebrew/Caskroom/nubrix", "/usr/local/Caskroom/nubrix"].contains { FileManager.default.fileExists(atPath: $0) })`. No arguments, returns only a bool, reads nothing else. The helper is needed because the sandboxed app can't see `/opt/homebrew`. It is a heuristic (brew has no API): a Caskroom entry with a source build running is still reported as a source build, because Team ID is checked first.

Version skew: the helper ships inside the same bundle, so app and helper always match. If the call fails (old helper, XPC error) the client returns `false` and the UI falls back to the release-zip instructions, which also work for Homebrew users.

## Version rules (`ReleaseVersion`)

- Tag: must match `^v(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$` over ASCII only (no `\d`, which matches non-ASCII digits). Rejected: `1.2.3`, `V1.2.3`, `v1.2`, `v1.2.3.4`, `v1.2.3-beta.1`, `v1.2.3+build`, `v01.2.3`, leading/trailing whitespace, `v１.2.3` (full-width), components over 6 digits, empty.
- Bundle version (`CFBundleShortVersionString`): same component rule without the `v`; `X.Y` is accepted as `X.Y.0`. Anything else → `nil`, and the store reports `.failed(.unknownCurrentVersion)` instead of guessing.
- Ordering: lexicographic on `(major, minor, patch)`, numeric (`0.10.0 > 0.9.9`).

## Response rules (`UpdateParsing.latestVersion`)

- Body over 1 MiB → `.malformed`.
- Decode only `tag_name: String`, `draft: Bool?`, `prerelease: Bool?` with `JSONDecoder`; unknown fields ignored. Missing/non-string `tag_name` or non-object JSON → `.malformed`.
- `draft == true` or `prerelease == true` → `.notEligible` (`releases/latest` should never return these; this is defence in depth).
- `tag_name` that fails `ReleaseVersion(tag:)` → `.invalidTag`.
- Nothing else from the response (URLs, `body`, `name`, assets) is read or shown.

## Decision (`UpdateDecision.evaluate(latest:current:skipped:)`)

- `latest <= current` → `.upToDate` (equal = up to date; lower = downgrade, ignored).
- `latest > current` and `skipped == latest.tag` → `.skipped(latest)`.
- otherwise → `.available(latest)`. A release newer than the skipped one shows again.

## Network (`UpdateClient`)

- `URL`: `https://api.github.com/repos/murathanbakti/nubrix/releases/latest` (constant; injectable for tests).
- Session: `URLSessionConfiguration.ephemeral`, `urlCache = nil`, `.reloadIgnoringLocalCacheData`, `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `urlCredentialStorage = nil`, timeouts 15 s / 30 s. Tests inject a configuration with a `URLProtocol` stub.
- Headers: `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `User-Agent: Nubrix/<version>`. Never `Authorization`; never the GitHub token from Keychain.
- Redirects: per-task delegate `UpdateNoRedirect` answers `completionHandler(nil)`, so a 3xx comes back as the final response → `.redirected`.
- Status: 200 → parse; 403/429 with `x-ratelimit-remaining: 0` or `retry-after` → `.rateLimited`; 404 → `.notFound` (no published release); 3xx → `.redirected`; other → `.http(code)`; transport error → `.network`. The final response URL's host must be `api.github.com` with scheme `https`, else `.redirected`.

`enum UpdateFailure: Error, Equatable { network, http(Int), rateLimited, notFound, redirected, malformed, invalidTag, notEligible, unknownCurrentVersion }` with a short user-facing `message`.

## Defaults (`UpdateDefaults.swift`)

- `updateAutoCheck: Key<Bool?>` — `nil` = never asked, `false` = declined, `true` = daily check on. Default `nil`; nothing is sent until the user turns it on or presses Check now.
- `updateLastCheck: Key<Date?>` — last *successful* check.
- `updateLatestVersion: Key<String?>` — last validated tag seen (re-validated on load).
- `updateSkippedVersion: Key<String?>` — tag the user skipped.

## Scheduling (`UpdateSchedule.isDue`)

```swift
static func isDue(autoCheck: Bool?, lastSuccess: Date?, lastAttempt: Date?, now: Date,
                  interval: TimeInterval = 86_400, retryAfterFailure: TimeInterval = 3_600) -> Bool
```

- `autoCheck != true` → false.
- `lastAttempt` within `retryAfterFailure` of `now` → false (no hammering when offline).
- `lastSuccess == nil`, or `now - lastSuccess >= interval`, or `lastSuccess > now + 300` (clock moved back) → true; else false.

`lastAttempt` lives in memory only.

## State machine (`UpdateStore`)

```
enum UpdateCheckState: Equatable { idle, checking, upToDate, available(ReleaseVersion), skipped(ReleaseVersion), failed(UpdateFailure) }
```

- `idle` → (`checkNow()` or a due auto check) → `checking`.
- `checking` → `upToDate` / `available(v)` / `skipped(v)` on success (also writes `updateLastCheck`, `updateLatestVersion`); → `failed(e)` on error (writes nothing but in-memory `lastAttempt`).
- Any → `checking` again on the next trigger; a trigger while `checking` is ignored.
- `skip()` while `available(v)` → writes `updateSkippedVersion = v.tag`, state → `skipped(v)`. `unskip()` clears it and re-evaluates.
- `start()`: resolves `installKind` (Team ID synchronously, Homebrew via the helper, async), restores state from `updateLatestVersion` through `UpdateDecision.evaluate` (so the banner disappears after the user updates), creates an `NSBackgroundActivityScheduler` (`dev.nubrix.app.update-check`, interval 86 400 s, tolerance 3 600 s, `.utility`, repeats) whose block hops to the main actor and runs `checkIfDue()`, runs `checkIfDue()` once 20 s after launch, and again on `NSWorkspace.didWakeNotification` and when `updateAutoCheck` changes to `true`. `stop()` invalidates the scheduler and observers.
- Published: `state`, `installKind`, `lastCheck`. Computed: `availableVersion: ReleaseVersion?` (only for `.available`).
- Testability: `UpdateStore` takes `fetch: @Sendable () async throws -> ReleaseVersion` (throws `UpdateFailure`), `currentVersion: String?`, `now: () -> Date` and a `Defaults`-independent `UpdatePreferences` protocol (Defaults-backed in the app, in-memory in tests). `shared` uses the real ones. Under XCTest nothing starts on its own.

## Install types

`UpdateInstallKind.resolve(teamIdentifier:isHomebrew:)`: Team ID ≠ `399MAAJ7QT` (or nil) → `.sourceBuild`; else `isHomebrew` → `.homebrew`; else `.releaseZip`.

`UpdateInstructions` (`summary`, `command`, `showsViewRelease`, `hooksReminder`):

| Kind | Summary | Command |
|---|---|---|
| `.homebrew` | "Installed with Homebrew. Update in Terminal:" | `brew upgrade --cask nubrix` |
| `.releaseZip` | "Download it from the release page, or run the install script again:" | `curl -fsSL https://raw.githubusercontent.com/murathanbakti/nubrix/main/scripts/install.sh \| bash` |
| `.sourceBuild` | "Built from source. In your checkout:" | `git pull && scripts/install-local.sh` |

All three show "View release" (URL built locally: `https://github.com/murathanbakti/nubrix/releases/tag/<validated tag>`) and the reminder "After updating, run install-hooks.sh again so the sealed hook copies match the new version, then reopen Nubrix." For `.homebrew` and `.releaseZip` the reminder includes `bash /Applications/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh`; for `.sourceBuild`, `install-local.sh` already runs it, so the reminder says so.

`AppSigningIdentity.teamIdentifier()` is the same `SecCodeCopySelf` → `SecCodeCopyStaticCode` → `kSecCodeInfoTeamIdentifier` code as `ownTeamIdentifier()` in `NubrixHelper/main.swift`, validated as 10 uppercase ASCII letters/digits.

## UI

Settings → About, new section "Updates" (`UpdatesSettingsSection`):
- When `updateAutoCheck == nil`: a row "Check for new versions once a day?" with "Turn on" / "Not now" (sets `true` / `false`).
- Toggle "Check for updates once a day" (shown once asked).
- Status row: "Never checked" / "Checking…" / "Nubrix is up to date" / "Version X.Y.Z is available" / "Version X.Y.Z skipped" / "Couldn't check: <message>", plus "Last checked <relative date>" when known; trailing "Check now" button (disabled while checking).
- When available: summary, the command in a monospaced selectable text with a Copy button, "View release", "Skip this version", and the hooks reminder. When skipped: "Show again" (`unskip()`).
- Section footer: "Asks api.github.com for the latest release, without your GitHub token. Nothing is downloaded or installed."
- No remote text (release notes, names, URLs) is rendered.

Menu bar (`UpdateMenuItems`, above Settings, followed by a `Divider`):
- `.available(v)` → "Update available: X.Y.Z…" → `SettingsNavigation.shared.open("About")`.
- `updateAutoCheck == nil` → "Turn on update checks…" → opens About.
- Always: "Check for Updates…" → `checkNow()` and opens About.

## Docs

- `README.md`: "Local only" bullet — replace "no auto-updater" with "no auto-updater (an optional daily check only asks GitHub for the latest version number)", and add `api.github.com` release check to the network sentence; "Updating" — mention Settings → About → Updates.
- `docs/nubrix/PRIVACY-AND-SECURITY.md`: "Local only" — same wording; "Network use" — new bullet: `api.github.com/repos/murathanbakti/nubrix/releases/latest` when you press Check now or turn on the daily check (off by default); no token, no cookies, no identifiers beyond IP and `User-Agent: Nubrix/<version>`; redirects refused; only `tag_name` is read; nothing downloaded or run; stored: last check date, latest and skipped version.
- `docs/nubrix/ROADMAP.md`: move "An update mechanism" from Remaining to done as "Update check (notify only)", keep Sparkle as a possible later step.

## Tests (`NubrixTests/Updates/`, no real network)

- `ReleaseVersionTests`: valid tags; every rejected form listed above; bundle version `X.Y.Z` / `X.Y` / garbage; ordering incl. `0.10.0 > 0.9.9`, equality.
- `UpdateParsingTests`: minimal JSON; extra fields ignored; `draft: true` / `prerelease: true` → `.notEligible`; missing `tag_name`, number `tag_name`, array root, empty data, > 1 MiB → `.malformed`; pre-release tag string → `.invalidTag`.
- `UpdateDecisionTests`: newer → available; equal → upToDate; older (downgrade) → upToDate; skipped equal → skipped; newer than skipped → available.
- `UpdateScheduleTests`: off (`nil`, `false`) → never; on + never checked → due; on + 1 h ago → not due; on + 25 h ago → due; recent failed attempt → not due; clock moved back → due.
- `UpdateInstallKindTests`: resolve matrix (nil team, other team + Homebrew, release team ± Homebrew); instruction text and command per kind; release URL uses the validated tag only.
- `UpdateClientTests` (`URLProtocol` stub): 200 → version; request has no `Authorization`, has `User-Agent: Nubrix/…`, method GET, exact URL; 404 → `.notFound`; 403 + `x-ratelimit-remaining: 0` → `.rateLimited`; 302 → `.redirected` and the `Location` target is never requested; 500 → `.http(500)`; transport error → `.network`. Plus a direct test that `UpdateNoRedirect` passes `nil` to its completion handler.
- `UpdateStoreTests` (injected fetch, in-memory preferences): `checkIfDue` does nothing when off; with on + recent success it does not fetch; `checkNow` fetches regardless; success writes last check + latest; failure writes neither; skip/unskip; restore after app update (stored latest == current → upToDate).

## On-device checks (user)

1. Fresh prefs: no network request at launch (Little Snitch / `nettop`), menu shows "Turn on update checks…".
2. About → Updates → Check now on 0.1.1 with no newer release: "up to date". Temporarily build with `MARKETING_VERSION = 0.0.9` → "Version 0.1.1 is available", correct install-type text: Homebrew machine shows `brew upgrade --cask nubrix`, zip install shows install script, a local `install-local.sh` build shows the source text.
3. Copy button copies the exact command; View release opens `…/releases/tag/v0.1.1`.
4. Skip this version → menu item disappears, "Show again" restores it.
5. Turn on the daily check, relaunch: one request ~20 s after launch, none on the next relaunch within 24 h.
6. Offline: "Couldn't check" without a crash; no retry storm.
7. Helper: `isHomebrewInstall` works from the Developer ID build (helper code-signing requirement unchanged).
