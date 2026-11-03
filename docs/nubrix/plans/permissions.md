# Plan: no repeated permission prompts (2026-11-03)

Research: `docs/nubrix/research/permissions.md`. Branch: `murathan.bakti/permissions-d41051`.
Goal in one line: a fresh install shows no system dialog until a feature is used,
and "Quit & Reopen" after Full Disk Access brings the user back to where they were.

## 1. Changes by goal

### (a) Zero system prompts at launch: `PermissionClient`

New `Nubrix/Features/Permissions/PermissionClient.swift`:

```swift
enum AutomationTarget: String, CaseIterable { music = "com.apple.Music", spotify = "com.spotify.client",
                                              terminal = "com.apple.Terminal", iterm = "com.googlecode.iterm2" }
enum AppPermission: Hashable { accessibility, fullDiskAccess, camera, calendar, automation(AutomationTarget), pasteboard }
enum PermissionStatus: Equatable { granted, denied, notDetermined, unavailable }

@MainActor protocol PermissionClient: AnyObject {
    func status(_: AppPermission) async -> PermissionStatus   // never prompts
    func request(_: AppPermission) async -> PermissionStatus  // may prompt
    func openSystemSettings(_: AppPermission)
}
@MainActor enum Permissions { static var client: any PermissionClient = SystemPermissionClient() }
```

`SystemPermissionClient` is the only place in the app that calls a requesting API:

| Permission | status (no prompt) | request |
|---|---|---|
| accessibility | `XPCHelperClient.isAccessibilityAuthorized` → granted / notDetermined | `ensureAccessibilityAuthorization(promptIfNeeded: true)` |
| fullDiskAccess | `SystemNotificationStore.checkNow()`: ready → granted, noAccess → denied, off → notDetermined, other → unavailable | `FullDiskAccessGuide.begin(origin: .permissions)` |
| camera | `AVCaptureDevice.authorizationStatus(for: .video)` | `AVCaptureDevice.requestAccess` |
| calendar | `EKEventStore.authorizationStatus(for: .event)` | `SharedEventStore.shared.store.requestFullAccessToEvents()` |
| automation(t) | `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` off the main thread; -1744 → notDetermined, -1743 → denied, -600 / not running → unavailable | same with `true` if the target runs, else open Settings |
| pasteboard | `NSPasteboard.general.accessBehavior` (15.4+): alwaysAllow / default → granted, ask → notDetermined, alwaysDeny → denied | open Settings (no API) |

`openSystemSettings` opens `x-apple.systempreferences:com.apple.preference.security?Privacy_{Accessibility,AllFiles,Camera,Calendars,Automation,Pasteboard}`.

Call sites routed through `Permissions.client`:
- `Providers/CalendarServiceProviding.swift:32`, `Features/Calendar/NubrixCalendarStore.swift:101` → `request(.calendar)`
- `Features/Mirror/MirrorCamera.swift:86` → `request(.camera)`
- `NubrixCoordinator.swift:157` → `request(.accessibility)`; `:177-184` → extracted
  `static func verifyHUDAtLaunch(client:) async -> Bool` that uses `status(.accessibility)` only
- `observers/MediaKeyInterceptor.swift:38,60`, `components/Settings/SettingsView.swift:515` → `request(.accessibility)`
- `FullDiskAccessGuide.openSettings()` → `openSystemSettings(.fullDiskAccess)`

AppleScript seam in `helpers/AppleScriptHelper.swift`: `protocol AppleScriptRunning { func run(_:) async throws -> NSAppleEventDescriptor? }`,
`NSAppleScriptRunner` (today's body), `nonisolated(unsafe) static var runner`. `execute` keeps its signature.

Music (`managers/MusicManager.swift:248-261`, `models/Constants.swift:183-197`):
- `static func resolvedControllerType(preferred:nowPlayingDeprecated:) -> MediaControllerType?`
  returns `nil` for `.nowPlaying` when deprecated, else `preferred`. No Apple Music fallback.
- `defaultMediaController` is always `.nowPlaying` (it returned `.appleMusic` when deprecated).
- Apple Music / Spotify controllers only start when the user picked them, so their AppleScript
  (and the Automation dialog) follows a user choice.

Pasteboard (`Features/Clipboard/ClipboardMonitor.swift:137`): `ClipboardReadPolicy.automaticRead(_ behavior) -> Bool`
(true for default / alwaysAllow). With `.ask` the monitor does not read, sets `@Published needsPasteConsent`,
and Vitrin shows a pill "macOS asks before Nubrix reads copied items" with
"Save Copied Item" (user-initiated read, macOS shows its alert once) and "Allow in Settings…".
`.default` keeps today's behavior: the research saw no paste alerts on macOS 26.7 (to verify on device).

### (b) Onboarding and the FDA "Quit & Reopen" path: `LaunchFlow`

New `Nubrix/Features/Permissions/LaunchFlow.swift`, a value type over a `UserDefaults` (tests pass a private suite):

```swift
enum FDAOrigin: String { settings, notch, permissions }
enum LaunchAction: Equatable { none, onboarding, musicSource, fdaReturn(FDAOrigin) }
enum FDAReturnOutcome: Equatable { ready(FDAOrigin), stillOff(FDAOrigin) }
struct LaunchFlow {
    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init)
    func initialAction(musicSourceNeeded: Bool) -> LaunchAction
    func onboardingDidAppear()                  // firstLaunch = false
    func musicSourceDidAppear()                 // musicSourcePromptShown = true
    func beginFDAGrant(origin: FDAOrigin)       // fdaGrantPendingAt / fdaGrantPendingOrigin
    func pendingFDAOrigin() -> FDAOrigin?       // nil when missing or older than 30 min
    func clearFDAPending()
    func resolveFDAReturn(origin:client:) async -> FDAReturnOutcome  // status only, clears pending
    static func musicSourceNeeded(mediaControlEnabled:nowPlayingDeprecated:controller:) -> Bool
}
```

State machine at launch (`initialAction`):
1. valid FDA pending → `.fdaReturn(origin)`
2. `firstLaunch == true` → `.onboarding`
3. music source needed and `musicSourcePromptShown == false` → `.musicSource`
4. otherwise `.none`

`NubrixApp.swift`:
- `:457-469` → switch on `LaunchFlow().initialAction(...)`.
- `showOnboardingWindow` calls `onboardingDidAppear()` when it shows the window (not on close).
  `OnboardingView` `.musicPermission` calls `musicSourceDidAppear()` in `onAppear`.
- `applicationWillTerminate` calls `onboardingDidAppear()` if the onboarding window is open
  (a Quit Apple Event never closes windows, so `willClose` is not enough).
- `.fdaReturn(origin)`: `resolveFDAReturn` → navigate to the origin
  (`.settings` → `SettingsNavigation.shared.open("Notifications")`, `.permissions` → `open("Permissions")`,
  `.notch` → `coordinator.currentView = .notifications` + open the notch), then
  `.ready` → `FullDiskAccessGuide.showReturn(granted: true)` (success panel, closes after 4 s),
  `.stillOff` → `showReturn(granted: false)` (guide panel only; System Settings is not reopened).

`FullDiskAccessGuide.swift`:
- `begin(origin: FDAOrigin = .settings)`; writes the pending flag **before** opening System Settings.
- Pending is cleared when access turns ready while running and on the panel's Close button
  (not in `willClose`, which does not fire on quit).
- Step 3 text: "Choose Quit & Reopen. Nubrix comes back here."
- `SystemNotificationsTabView.swift:111` passes `.notch`; the other callers keep the default.

### (c) Defaults
Already off: `hudReplacement`, `systemNotificationsEnabled`, `enableLyrics`. Lazy (status only at launch):
`showCalendar`, `showMirror`, `meetingCountdownEnabled`, `vitrinEnabled`. Changed: `mediaController`
default, Apple Music fallback removed, music step at most once, pasteboard "ask" respected.

### (d) Settings → Permissions
New `components/Settings/PermissionsSettings.swift`: `PermissionsSettingsModel` (`@MainActor ObservableObject`,
`init(client:)`, `refresh()` reads status only) and the view. Sidebar entry "Permissions" (`lock.shield`)
after General in `SettingsView.swift`. Rows: Accessibility (HUDs, media keys), Full Disk Access
(notifications from other apps), Camera (Mirror), Calendar (calendar, meetings), Automation for Music,
Spotify, Terminal, iTerm (music source, session tab jump), Paste from Other Apps (Vitrin).
Pure mapping `static func action(for:status:) -> PermissionRowAction` (`.none`, `.grant`, `.openSettings`)
and `statusText`. Refresh on appear and on `NSApplication.didBecomeActiveNotification`.
Also fix the HUD text at `SettingsView.swift:507` ("access goes to NubrixHelper" → Nubrix).

### (e) Signing and bundle id
- Debug only (`project.pbxproj`): app `dev.nubrix.app.debug`, display name "Nubrix Debug";
  helper `dev.nubrix.app.debug.NubrixHelper`. Release stays `dev.nubrix.app` / `dev.nubrix.app.NubrixHelper`.
- `XPCHelperClient.swift:8`: service name = `Bundle.main.bundleIdentifier + ".NubrixHelper"`.
- `NubrixHelper/main.swift:26-29`: expected client id = helper's own bundle id minus `.NubrixHelper`
  (falls back to `dev.nubrix.app`); team check unchanged.
- Ripple: the test host becomes `dev.nubrix.app.debug` (own container `~/Library/Containers/dev.nubrix.app.debug`,
  own prefs, own TCC rows); `SmokeTests` updated. Not keyed on the bundle id, so shared with the real app:
  `~/.config/nubrix`, `~/.config/nubrix-run`, the `dev.nubrix.github` keychain item, Logger subsystem.
  No app groups. Release packaging (cask, install.sh) untouched.
- `scripts/sign-release.sh` local mode (`NUBRIX_SIGN_LOCAL=1`, used by install-local.sh): find the team
  from the identity (sign a scratch copy of `/usr/bin/true`, read `TeamIdentifier`) and sign the app and
  each XPC service with `-r='designated => anchor apple generic and identifier "<CFBundleIdentifier>" and certificate leaf[subject.OU] = "<team>"'`.
  A Developer ID build of the same team satisfies this DR, so grants made by a local build survive
  installing a release. The reverse (release grant → local build) needs releases signed with the same DR;
  that is the user's decision for v0.1.2 and is documented, not changed here.

## 2. Tests (`NubrixTests/Permissions/`, hermetic)
- `Fakes.swift`: `FakePermissionClient` (scripted statuses, records `statusCalls`, `requests`, `openedSettings`),
  `RecordingAppleScriptRunner`, private `UserDefaults` suite helper. Tests swap `Permissions.client` and
  `AppleScriptHelper.runner` in `setUp` and restore them in `tearDown`.
- `LaunchAuditTests`: fresh defaults → `initialAction == .onboarding`, `verifyHUDAtLaunch` with hud off and on
  (AX missing → returns false), `resolvedControllerType` with Now Playing deprecated, `PermissionsSettingsModel.refresh()`;
  assert no `requests`, no `openedSettings`, no AppleScript. Repeat with stored states (hud on, notifications on, deprecated).
- `OnboardingPersistenceTests`: onboarding appears → simulated relaunch (new `LaunchFlow` on the same suite) → `.none`;
  music step shown once.
- `FDAReturnTests`: pending + granted → `.fdaReturn` then `.ready(origin)`, pending cleared, no requests;
  pending + denied → `.stillOff`, no requests, no Settings opened; pending older than 30 min → ignored.
- `DefaultsAuditTests`: permission-backed keys default to off, or are on the lazy allowlist; `mediaController` default `.nowPlaying`.
- `PermissionsModelTests`: action/status-text mapping for every permission × status.
- `ClipboardPolicyTests`: `.ask` and `.alwaysDeny` → no automatic read.
- `PromptingAPIGuardTests`: scans `Nubrix/**/*.swift` (path from `#filePath`) and fails if a requesting
  API (`requestFullAccessTo`, `requestAccess(for:`, `kAXTrustedCheckOptionPrompt`, `NSAppleScript(`, `CGRequest`,
  `promptIfNeeded: true`, `.requestAccessibilityAuthorization()`) appears outside `PermissionClient.swift`,
  `AppleScriptHelper.swift`, `XPCHelperClient.swift`.

Run: `scripts/run-tests.sh ~/Library/Caches/Nubrix/DerivedData-permissions`, plus a Release build with
`CODE_SIGNING_ALLOWED=NO` to confirm the release bundle id is unchanged.

## 3. On-device checklist (user)
Watch: `log stream --predicate 'subsystem == "com.apple.TCC" AND (eventMessage CONTAINS "AUTHREQ_PROMPTING" OR eventMessage CONTAINS "Failed to match")'`
1. Fresh Developer ID build (new user account, or TCC reset + container prefs removed by the user):
   launch, finish onboarding → no system dialog.
2. Use each feature once (calendar pill, Mirror, HUD switch, Grant Access…, Music/Spotify source, tab jump,
   copy in another app with Vitrin) → one dialog per feature, then Settings → Permissions shows it granted.
3. FDA during onboarding: open the notch Notifications tab while onboarding is open, Grant Access → turn on →
   Quit & Reopen → no onboarding, notch Notifications open, "Access granted" panel.
4. FDA after onboarding from Settings → Notifications → same, Settings opens on Notifications.
   Turn it on but click "Later" instead → relaunch shows the guide panel only.
5. Quit and relaunch 3 times → no prompts, no onboarding, music step not repeated.
6. Release ↔ local: grant with an `install-local.sh` build, then install the release → no "Failed to match".
   The other direction still mismatches until releases use the team DR.
7. `run-tests.sh` and Xcode Debug runs → "Nubrix Debug" appears as its own entry; the installed app's grants are untouched.
8. Pasteboard on macOS 26.x: check Privacy & Security → Paste from Other Apps for Nubrix; with "Ask" set,
   Vitrin shows the pill instead of a system alert.

## 4. Merge notes
Shared files with the other branches: `NubrixApp.swift` (launch switch), `SettingsView.swift` (sidebar entry),
`AppleScriptHelper.swift` (tab jump adds Ghostty: add `AutomationTarget.ghostty` after merge),
`FullDiskAccessGuide.swift` / SystemNotifications (Dock badges; `begin()` keeps a default origin).
