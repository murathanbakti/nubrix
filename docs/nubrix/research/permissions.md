# Permission prompts at first launch and after "Quit & Reopen" (research, 2026-11-03)

User report: first launch still asks for every permission, and after granting
Full Disk Access (System Settings offers "Quit & Reopen") all permissions are
asked again.

## Findings in short

1. **The released build is the old onboarding.** `v0.1.1` is `a561597`, tagged
   2026-11-02 13:37. The fixes `5bf949e` (17:53), `5937a54` (18:16) and `9d54dc5`
   (18:29) came later and are not in any release. In `v0.1.1`,
   `OnboardingView.swift` walks through camera (`AVCaptureDevice.requestAccess`),
   calendar (`requestFullAccessToEvents`), Accessibility
   (`ensureAccessibilityAuthorization(promptIfNeeded: true)`) and then
   `FullDiskAccessGuide.begin()`, all **before** `firstLaunch = false`
   (`git show v0.1.1:Nubrix/components/Onboarding/OnboardingView.swift`, lines 60-160).
   Anyone installing the DMG or cask gets "every permission at first launch".
2. **Quit & Reopen during onboarding restarts onboarding.** `firstLaunch` is only
   cleared when the music step is confirmed (`OnboardingView.swift:45`) or on
   `NSWindow.willCloseNotification` (`NubrixApp.swift:632`). System Settings quits
   the app with a Quit Apple Event (log: `Nubrix[80064] Handling Quit AppleEvent`,
   23:51:19). `terminate:` does not close windows, so `willClose` never fires and
   `firstLaunch` stays `true`. On relaunch `NubrixApp.swift:457` shows onboarding
   again. In `v0.1.1` the FDA step is inside onboarding, so this always happens:
   the camera, calendar and Accessibility pages come back, and the
   Accessibility system dialog (`AXIsProcessTrustedWithOptions` with prompt,
   `NubrixHelper/NubrixHelper.swift:19-21`) appears again every time it is
   called while not trusted. It is not remembered like camera/calendar.
   Current source: onboarding no longer asks, but the notch works while
   onboarding is open (`9d54dc5`), so "Grant Access…" in the notch
   (`SystemNotificationsTabView.swift:111`, `SystemNotificationViews.swift:142`)
   followed by Quit & Reopen still brings onboarding back (no system dialogs,
   but the page lists all four permissions again).
3. **Grants are lost when the signature changes.** TCC and Keychain bind a grant
   to the app's designated requirement (DR). The same bundle id `dev.nubrix.app`
   is signed in three different ways:
   - Xcode Debug and the unit test host: ad-hoc (`"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-"`,
     `Nubrix.xcodeproj/project.pbxproj:1094,1119,1276,1331,1380,1402`). The test
     host runs as `dev.nubrix.app` from
     `~/Library/Caches/Nubrix/DerivedData-tests/.../Debug/Nubrix.app` (log, 09:39 and 09:40).
   - `scripts/install-local.sh`: Apple Development. DR pins the certificate CN:
     `identifier "dev.nubrix.app" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: …" and certificate 1[field.1.2.840.113635.100.6.2.1]`.
   - Releases: Developer ID. That DR pins the Developer ID OIDs and the team OU.
   None of these DRs match each other. tccd then logs "Failed to match existing
   code requirement" and treats the grant as missing, so camera/calendar ask
   again, Accessibility shows its dialog again, and Full Disk Access looks on in
   System Settings but does not work until it is toggled again (which triggers
   another Quit & Reopen). The GitHub token in the file-based Keychain gets the
   same treatment ("Nubrix wants to use … dev.nubrix.github").
4. **On this Mac, the current build does not prompt at launch.** In three days of
   tccd logs there is exactly one `AUTHREQ_PROMPTING` for Nubrix (camera, when
   Mirror was opened). Everything at launch is `preflight=yes`. See Evidence below.

## 1. Inventory of protected-resource access (current source)

"Launch" = runs from `applicationDidFinishLaunching` (`NubrixApp.swift:300-470`) or
`NubrixCoordinator.init` without user action.

| Resource | Code | At launch? | Gate (default) | Prompts? |
|---|---|---|---|---|
| Calendar status | `CalendarManager.swift:32`, `NubrixCalendarStore.swift:61`, `MeetingWatcher.swift:135`, `TodayTile.swift:85` | Yes (status only) | `showCalendar` (**true**), `meetingCountdownEnabled` (**true**) | No. `EKEventStore()` at `SharedEventStore.swift:48` makes calaccessd preflight Calendar **and Reminders** |
| Calendar request | `CalendarManager.swift:90` via `checkCalendarAuthorization` (buttons `SettingsView.swift:810`, `MeetingSettingsSection.swift:35`); `NubrixCalendarStore.swift:101` (pill `NubrixCalendarDayPanel.swift:188`) | No | button | Yes, once |
| Camera | `MirrorCamera.swift:66` (status), `:86` (request, from `MirrorMode.swift:58`) | No | `showMirror` (**true**), lazy | Yes, once, on "Turn On Camera" |
| Camera device list | `SettingsView.swift:1418` `AVCaptureDevice.default` | No | — | No |
| Accessibility check | `NubrixCoordinator.swift:177-184` → `XPCHelperClient.isAccessibilityAuthorized` | Yes, only if `hudReplacement` | `hudReplacement` (false) | No; turns the switch off if not trusted |
| Accessibility prompt | `NubrixHelper.swift:19-36`, via `XPCHelperClient.swift:100,130`, `NubrixCoordinator.swift:157` (switch turned on), `SettingsView.swift:515` (button), `MediaKeyInterceptor.swift:38,60` | No | button / switch | Yes, **every call** while not trusted |
| Event tap | `MediaKeyInterceptor.swift:68` `CGEvent.tapCreate` | Only if `hudReplacement` and trusted | `hudReplacement` (false) | No |
| Input Monitoring preflight | global mouse monitors `DragDetector.swift:57,67,95`, `NotchExtensionHost.swift:385`; `CGEventSource.secondsSinceLastEventType` in `ClipboardMonitor` | Yes | `nubrixShelf` + `expandedDragDetection` (**true**), `vitrinEnabled` (**true**) | No (log: `kTCCServiceListenEvent preflight=yes` at every launch) |
| Full Disk Access | helper reads the notification DB (`NubrixHelper.swift:151-160`, `SystemNotificationReader.swift`); started by `SystemNotificationStore.start` (`NubrixApp.swift:310`) | Yes, only if enabled | `systemNotificationsEnabled` (false) | No dialog; the first denied read adds Nubrix, switched off, to the FDA list (log 18:19:24 `Create kTCCServiceSystemPolicyAllFiles`) |
| FDA guide | `FullDiskAccessGuide.swift:11-27` (sets `systemNotificationsEnabled = true`, opens Settings, shows panel) | No | buttons | Settings pane + Quit & Reopen |
| Automation: Music | `AppleMusicController.swift:34-40` (AppleScript if Music is running), `:43-51` (on every `com.apple.Music.playerInfo`) | **Yes, if this controller is active** | `mediaControlEnabled` (**true**) + `mediaController`; `MusicManager.swift:252-260` switches to Apple Music **automatically** when Now Playing is deprecated or cannot be created | Yes, "Nubrix wants to control Music" at launch with no choice by the user |
| Automation: Spotify | `SpotifyController.swift:41-47` | Same, if chosen | `mediaController` | Yes |
| Automation: Terminal/iTerm | `AppleScriptHelper.swift:15` from the session tab jump | No | `claudeOpenSession` (true) | Yes, on first click |
| Now Playing | `mediaremote-adapter.pl` via `/usr/bin/perl` (`MediaChecker.swift:27-32`) | Yes | `mediaControlEnabled` | No |
| Onboarding music step | `NubrixApp.swift:460-468` shows onboarding at `.musicPermission` on **every** launch while Now Playing is deprecated and the stored controller is `.nowPlaying` | Yes | as stated | In-app, repeats |
| Pasteboard | `ClipboardMonitor.swift:130-170` reads `NSPasteboard.general` on each change | Yes, from the first copy | `vitrinEnabled` + capture switches (**all true**) | Possibly: macOS 15.4+ "Paste from other apps" alert when `accessBehavior == .ask`. Not seen in logs; verify on macOS 26.7 |
| Screenshot folder | `ScreenshotAccess.swift:21-46` resolves a saved security-scoped bookmark; `:50` opens `NSOpenPanel` | Restore only | Vitrin (true); the panel is user-initiated (`ScreenshotBanner.swift:126`, `VitrinSettings.swift:64`) | No system prompt |
| Keychain (GitHub token) | `GitHubTokenStore.swift:22-30` | Yes, only if `githubTokenSaved` | `githubEnabled` (**true**) + token saved | Yes, after a signature change (file-based keychain ACL) |
| Claude plan usage | helper `ClaudePlanUsageProbe.swift:406-425` runs `claude` via `launchctl submit` | 3 s after launch | `claudeEnabled` + `claudePlanUsageEnabled` (**true**) | No TCC; the CLI is its own launchd job |
| Local server | `AgentEventServer.swift:88-90` loopback only, `acceptLocalOnly` | Yes | `claudeEnabled` / `devEnabled` | No (no Local Network or firewall prompt) |
| Microphone preflight | CoreAudio/AVAudio init (`VolumeManager.swift:104-113`, `MediaKeyInterceptor.swift:172`) | Yes | — | No (log: preflight only, "requires entitlement com.apple.security.device.audio-input but it is missing") |
| Not used | `UNUserNotificationCenter`, ScreenCaptureKit / `CGRequestScreenCaptureAccess`, location, Bluetooth, contacts in app code | — | — | — |

So, in current source, none of the **default-on** features calls a requesting
API at launch. The ones that can still prompt without a clear user action:
the automatic Apple Music fallback (Automation), Vitrin's pasteboard reads on
macOS 15.4+ (to verify), and anything whose earlier grant was stored under
another signature.

## 2. The FDA "Quit & Reopen" path

1. "Grant Access…" → `FullDiskAccessGuide.begin()` (`FullDiskAccessGuide.swift:11`):
   sets `systemNotificationsEnabled`, opens `Privacy_AllFiles`, shows a floating
   panel that is not saved anywhere.
2. The user turns on Nubrix. System Settings sends a Quit Apple Event. AppKit
   terminates normally (`replyToApplicationShouldTerminate:YES`), runs
   `applicationWillTerminate` (`NubrixApp.swift:73`), and the preferences are
   already in cfprefsd, so nothing is lost. `quitOnTerminationSignal`
   (`NubrixApp.swift:285`) only handles SIGTERM (install-local's `pkill -TERM`)
   and also ends in `NSApp.terminate`. It is not involved here.
3. Relaunch (`Successfully spawned Nubrix[80329]`, 23:51:23):
   - If onboarding was still open → `firstLaunch` is still `true` → onboarding
     again (cause 2 above).
   - The guide panel is gone. The Settings window is not restored:
     `isRestorable = true` (`SettingsWindowController.swift:53`) has no
     `restorationClass`, so it has no effect. The user is not brought back to
     Notifications and gets no "it worked" message.
   - No code asks again because a status is `.notDetermined` at launch (checked
     every path above). Such requests only happen behind buttons.
   - If the build that got the grant is signed differently from the one that
     relaunches (cause 3), every grant fails its csreq match and the features ask again.
   - The XPC helper is not a separate TCC client. Its requests are attributed to
     `dev.nubrix.app` (log 15:24:03: helper pid 45499, "subject dev.nubrix.app").
     Accessibility and FDA are therefore granted to "Nubrix", not to
     `NubrixHelper` (`PERMISSIONS-AND-SETTINGS.md` says otherwise and should be corrected).
   - Automation answers are remembered per target, also tied to the csreq.

## 3. Evidence from this Mac (read-only)

Installed app: `/Applications/Nubrix.app` 0.1.1 (build 2), signed 2026-11-03 00:23
(after `77dfe57`, so it contains the fixes). `Authority=Apple Development: …`,
`TeamIdentifier=399MAAJ7QT`, hardened runtime, sandboxed (entitlements: camera,
calendars, apple-events with exceptions for Spotify/Music/Terminal/iTerm,
user-selected files, network client/server). Helper not sandboxed and signed with the same identity.

Container prefs (`~/Library/Containers/dev.nubrix.app/Data/Library/Preferences/dev.nubrix.app.plist`):
`firstLaunch = 0`, `hudReplacement = 0`, `systemNotificationsEnabled = 1`,
`mediaController = "Now Playing"`, `nowPlayingDeprecated.<macOS 26.7.1>.2 = 0`,
`vitrinScreenshotFolderBookmark` set, `vitrinScreenshotPromptDismissed = 0`,
`nubrixMigrationVersion = 1`. There is no `dev.nubrix.app.plist` in `~/Library/Preferences`.

tccd, 2026-11-01 to 2026-11-03, 15 launches of `/Applications/Nubrix.app`:

| Time | What |
|---|---|
| every launch | `ListenEvent` preflight; `Microphone` preflight (until 18:21); calaccessd preflights Calendar + Reminders |
| 13:53 → 16:44 | at each launch "Failed to match existing code requirement" for **Calendar** and **Reminders** (grant stored under another signature) |
| 15:24:03 | helper Accessibility request, csreq mismatch → denied → Accessibility dialog; 15:42-15:44 the user toggles Accessibility in Settings (Modify/Delete/Modify) |
| 17:43:14 | Camera: csreq mismatch, then `AUTHREQ_PROMPTING kTCCServiceCamera` (Mirror), granted. **The only prompt in 3 days** |
| 18:18:21-25 | Calendar, Camera, Accessibility, FDA rows for Nubrix deleted (reset for a fresh test) |
| 18:19:24 | FDA row created, off (helper read the DB because `systemNotificationsEnabled` survived the reset) |
| 23:51:18 | FDA switched on (Modify); 23:51:19 Quit Apple Event; 23:51:23 relaunch: only preflights, no prompts |
| 00:23 → 09:39 | Reminders csreq mismatch keeps appearing at each launch (stale row, nothing asks for Reminders) |
| 09:39-09:40 (Nov 3) | Test host (ad-hoc Debug, same bundle id) launches: FDA csreq mismatch, AddressBook preflight |

`AUTHREQ_*` counts for Nubrix PIDs: 44 requests, 43 `preflight=yes`, 1 prompt.
The user TCC.db itself cannot be read without FDA (not attempted further).

## 4. Fixes

**(a) Zero system prompts at first launch**
1. Release the current source (v0.1.2). This alone removes the in-onboarding
   camera/calendar/Accessibility/FDA requests that users of 0.1.1 see.
2. `MusicManager.swift:252-260`: never fall back to Apple Music automatically.
   If Now Playing is unavailable, use no controller and show "Choose a music
   source" in the music view. `AppleMusicController`/`SpotifyController` init:
   do not send AppleScript until the user has picked that source
   (`mediaControllerChosenByUser` flag).
3. `NubrixApp.swift:460-468`: show the music step at most once (persist
   `musicSourcePromptShown`), not on every launch.
4. Vitrin pasteboard: on macOS 15.4+ check `NSPasteboard.general.accessBehavior`
   in `ClipboardMonitor.tick` (`ClipboardMonitor.swift:137`). If `.ask`, do not
   read contents. Show an in-app "Allow Vitrin to read copied items" pill
   instead, and read only after that. Treat `.alwaysDeny` as it is today.
5. Keep the rule "status only at launch" and enforce it with the audit test below.

**(b) Relaunch after granting FDA returns to the same place, with no repeated prompts or onboarding**
1. Onboarding state: write completion when the onboarding window **appears**
   (`onboardingVersionSeen = 1`), or at the latest in `applicationWillTerminate`
   if the window is open. Replace the `@AppStorage("firstLaunch")`
   (`NubrixCoordinator.swift:60`) check with that key, so a Quit Apple Event can
   never restart onboarding.
2. `FullDiskAccessGuide.begin()`: persist `fdaGrantPending = {date, origin}`
   (origin = settings tab or notch tab). In `applicationDidFinishLaunching`, if
   it is pending and less than 15 minutes old, run `SystemNotificationStore.checkNow()`:
   - `.ready` → clear the flag, open the notch Notifications tab or
     `SettingsNavigation.shared.requested = "Notifications"`, show a short
     "Full Disk Access is on" banner.
   - `.noAccess` → reopen the guide panel. Do not open System Settings again by itself.
3. Guide text: say "Choose Quit & Reopen; Nubrix will come back here".
4. Remove `isRestorable = true` from `SettingsWindowController.swift:53` (it does
   nothing without a restoration class), or implement a restoration class. Item 2 covers the need.
5. Signing (stops "asks again" after reinstalling):
   - Sign every local build with a team-based DR that the release certificate
     also satisfies. In `sign-release.sh` local mode, pass
     `-r='designated => identifier "dev.nubrix.app" and anchor apple generic and certificate leaf[subject.OU] = "399MAAJ7QT"'`
     (and `dev.nubrix.app.NubrixHelper` for the helper). Apple Development and
     Developer ID leaf certificates both carry the team in subject.OU. Then a
     grant made by the release survives `install-local.sh` and the other way
     round. Verify with `codesign -v -R='<DR>'` against a release build before relying on it.
   - Give Debug and the test host a different bundle id (`dev.nubrix.app.debug`)
     and their own container. Ad-hoc test runs then stop overwriting or
     invalidating the real app's TCC rows, preferences and container (this also
     avoids the macOS 14+ "access data from other apps" container prompt).
   - Optional: move the GitHub token to the data protection keychain
     (`kSecUseDataProtectionKeychain`, needs a keychain-access-groups entitlement)
     so the item is bound to the team rather than to a per-binary ACL.
6. Docs: Accessibility and FDA are granted to "Nubrix" (responsible process), not to `NubrixHelper`.

**(c) Defaults**
Features that need a permission are already off or lazy: `hudReplacement` and
`systemNotificationsEnabled` are false; calendar, Mirror and meetings only read
status. Remaining items: Apple Music fallback (a.2), Vitrin pasteboard (a.4).
Keep `showCalendar`/`showMirror` default on. They are safe as long as the
audit test passes.

**(d) One Permissions overview in Settings**
There is none today: the controls are spread over Calendar (`SettingsView.swift:795-815`),
HUDs (`:495-525`), Appearance/Mirror, Vitrin, Notifications and Meetings. Add a
"Permissions" tab built on a single `PermissionClient`:

| Row | Status API (no prompt) | Grant action |
|---|---|---|
| Calendar | `EKEventStore.authorizationStatus(for: .event)` | `requestFullAccessToEvents`, else open `Privacy_Calendars` |
| Camera | `AVCaptureDevice.authorizationStatus(for: .video)` | `requestAccess`, else open `Privacy_Camera` |
| Accessibility | helper `AXIsProcessTrusted` | helper prompt + open `Privacy_Accessibility` |
| Full Disk Access | `SystemNotificationStore.checkNow()` status | `FullDiskAccessGuide.begin()` |
| Automation (Music, Spotify, Terminal, iTerm) | `AEDeterminePermissionToAutomateTarget(…, askUserIfNeeded: false)` (only reliable while the target runs; otherwise "Not asked yet") | send a harmless event with `askUserIfNeeded: true`, else open `Privacy_Automation` |
| Screenshot folder | `ScreenshotAccess.shared.hasAccess` | `requestAccess()` |
| Pasteboard | `NSPasteboard.general.accessBehavior` | open Settings → Privacy & Security → Paste from Other Apps |

Each row shows status, a "Grant" or "Open System Settings" button and the
feature it is for. Refresh on `NSApplication.didBecomeActiveNotification`. The
tab's `onAppear` must only read status. The existing per-tab buttons call the same client.

## 5. Test plan

**Unit tests (NubrixTests, `scripts/run-tests.sh`)**
- Add `protocol PermissionClient { func status(_: Permission) -> PermissionStatus; func request(_: Permission) async -> PermissionStatus }`
  and an `AppleScriptRunning` seam. Route `CalendarService.requestAccess`,
  `NubrixCalendarStore.requestAccess`, `MirrorCamera.requestAccess`,
  `XPCHelperClient.request/ensureAccessibility…`, `FullDiskAccessGuide`,
  `AppleScriptHelper.execute` and `ScreenshotAccess.requestAccess` through them.
- Move the body of `applicationDidFinishLaunching` into
  `AppBootstrap.start(defaults:permissions:scripts:presenter:)`.
- `LaunchAuditTests`: with an empty `UserDefaults(suiteName:)` (all defaults) run
  the bootstrap and assert `permissions.requests.isEmpty` and `scripts.executed.isEmpty`.
  Repeat for stored states: `hudReplacement = true` without AX,
  `systemNotificationsEnabled = true`, Now Playing deprecated, Music running,
  `firstLaunch = true`.
- `OnboardingPersistenceTests`: show onboarding, call `applicationWillTerminate`
  without closing the window, bootstrap again → onboarding not presented.
- `FDAReturnTests`: `fdaGrantPending` with fake status `.ready` →
  `SettingsNavigation.requested == "Notifications"`, flag cleared, no
  `request` calls; with `.noAccess` → guide presented once, System Settings not opened.
- `DefaultsAuditTests`: table of keys whose features need a permission. Each must
  default to false or be on an explicit "lazy" allowlist (`showCalendar`,
  `showMirror`, `meetingCountdownEnabled`, `vitrinEnabled`).
- Source guard (script or test): the requesting APIs (`requestFullAccessTo`,
  `AVCaptureDevice.requestAccess`, `kAXTrustedCheckOptionPrompt`, `NSAppleScript(`,
  `CGRequest*Access`, `SCShareableContent`, `requestAuthorization`) may only
  appear in the `PermissionClient`/`AppleScriptRunning` implementations.

**On device (cannot be unit tested)**
Prepare (done by the user): a fresh macOS user account, or
`tccutil reset All dev.nubrix.app` plus deleting the container prefs.
While testing, watch:
`log stream --predicate 'subsystem == "com.apple.TCC" AND (eventMessage CONTAINS "AUTHREQ_PROMPTING" OR eventMessage CONTAINS "Failed to match")'`.
1. Install the **Developer ID** build and launch it. Expect no system dialog and
   no `AUTHREQ_PROMPTING` while finishing onboarding.
2. Use each feature once (calendar pill, Mirror, HUD switch, Grant Access…,
   Spotify/Music source, Terminal tab jump, copy text in another app with
   Vitrin on). Expect exactly one dialog per feature and none for the
   pasteboard (or the in-app pill if `.ask`).
3. FDA while onboarding is still open, and again after onboarding: Grant
   Access → turn on → Quit & Reopen. Expect no onboarding, the Notifications
   view opened, the "Ready" banner, and no prompts.
4. Quit and relaunch 3 times: no prompts, no "Failed to match".
5. Signing switch: grant everything with the release, run `install-local.sh`,
   launch. With the team DR expect no "Failed to match" and no repeated
   prompts. Also run `run-tests.sh` and confirm the installed app's grants are untouched.
6. Pasteboard on macOS 26.7: check whether a "Paste from other apps" alert
   appears and what `accessBehavior` reports.
