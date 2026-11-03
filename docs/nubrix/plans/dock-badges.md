# Plan: Dock badge counts without Full Disk Access

Source: `docs/nubrix/research/dock-badges.md` (decision: LaunchServices `StatusLabel`
read in the sandboxed main app through private SPI loaded with `dlsym`).

## Goal

Show the unread number that chosen apps put on their Dock icon (WhatsApp, Slack, Mail, …)
in the notch, with no permission prompt. Separate switch "Show unread counts", off by
default. Works alongside or instead of "Show notifications from other apps" (Full Disk
Access). Badges never feed `NubrixInbox`.

## Merge hygiene

Five branches merge into `nubrix` afterwards. New code lives in new files under
`Nubrix/Features/SystemNotifications/DockBadges/` (synchronized group, no pbxproj edit).
Edits to shared files are small, additive lines. `FullDiskAccessGuide.swift`,
`NubrixHelper/` and the XPC protocol are not touched. The `.noAccess` status row gets
one extra button only (the permissions session also edits around that row).

## New files

### `DockBadges/DockBadgeDefaults.swift`
- `Defaults.Keys.dockBadgesEnabled = Key<Bool>("dockBadgesEnabled", default: false)`.
- App list is shared: `systemNotificationApps`.

### `DockBadges/DockBadgeModels.swift` (pure, fully unit tested)
- `struct DockBadge: Equatable, Identifiable { bundleID; label; count: Int? }`, `id = bundleID`,
  `weight = count ?? 1`.
- `enum DockBadgeLabel { static func parse(_ raw: String?) -> (label: String, count: Int?)? }`
  - nil, empty or whitespace only → nil (no badge).
  - trimmed digits only → count; `"0"` / `"0+"` → nil (no badge).
  - digits followed by `+` (`"99+"`) → count = the number, label kept as is.
  - anything else (`"•"`, `"!"`, `"new"`) → count nil, label kept (shown as a dot / raw).
  - label longer than 8 characters is cut to 8.
- `struct DockBadgeSummary { badges sorted; total; top }` built from `[DockBadge]` and
  the chosen-app order: `total` = sum of `weight`; `top` = highest weight, ties by
  chosen-app order, then bundle ID. `totalText` = `"99+"` above 99.
- `enum DockBadgeAppList { static func rows(known:allowed:running:defaults:ownBundleID:isInstalled:) -> [String] }`
  dedupes the union of known (FDA list), allowed (ticked), running regular apps
  (a badged app is running, so it is covered), and installed defaults (`net.whatsapp.WhatsApp`, `desktop.WhatsApp`,
  `com.apple.MobileSMS`, `com.apple.mail`, `com.tinyspeck.slackmacgap`,
  `com.microsoft.teams2`, `ru.keepcoder.Telegram`, `com.hnc.Discord`); allowed are kept even
  if not installed; defaults only if installed; own bundle ID removed; sorted by bundle ID
  (the view re-sorts by display name).

### `DockBadges/DockBadgeReader.swift`
- `protocol DockBadgeReading { var isAvailable: Bool { get }; func read(bundleIDs: [String]) -> DockBadgeReadResult; func runningRegularApps() -> [String] }`
- `struct DockBadgeReadResult: Equatable { running: Set<String>; labels: [String: String] }`
  (labels are raw, parsing happens in the store).
- `final class LaunchServicesDockBadgeReader: DockBadgeReading`
  - `dlopen` LaunchServices (`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices`), falling back to `RTLD_DEFAULT`;
    `dlsym` `_LSASNCreateWithPid` (`(CFAllocator?, pid_t) -> Unmanaged<CFTypeRef>?`, +1) and
    `_LSCopyApplicationInformationItem` (`(Int32, CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?`, +1),
    session `-2`, key `"StatusLabel"`. Missing symbol → `isAvailable == false`, `read`
    returns only `running` with no labels. Never force-unwrap, never crash.
  - Value handling: `CFDictionary` with `"label"` → `String` if `CFString`; a bare
    `CFString` is accepted too; anything else → no label.
  - `label(forPID:)` is public for the real-reader test.
  - pids from `NSRunningApplication.runningApplications(withBundleIdentifier:)`; skips
    terminated apps; first instance with a label wins.
  - `runningRegularApps()` → `NSWorkspace.shared.runningApplications` with
    `.regular` policy and a bundle ID.

### `DockBadges/DockBadgeStore.swift`
- `@MainActor final class DockBadgeStore: ObservableObject`, `static let shared` built
  with the real reader, `TaskDockBadgeScheduler` and `DefaultsDockBadgeSettings`.
- Injection for tests:
  - `protocol DockBadgeSettings { var isEnabled: Bool { get }; var apps: [String] { get } }`.
  - `@MainActor protocol DockBadgeScheduling { func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> DockBadgeCancellable }`,
    `@MainActor protocol DockBadgeCancellable { func cancel() }`.
    Real one: `Task { try? await Task.sleep(for: .seconds(s), tolerance: .seconds(s / 4)); … }`.
- Published: `status: DockBadgeStatus` (`.off`, `.ready`, `.unavailable`),
  `summary: DockBadgeSummary`. Helpers `total`, `top`, `badge(for:)`, `count(for:)`.
- Internal for tests: `isPolling` (a tick is scheduled), `readCount` not needed (fake reader counts).
- Lifecycle:
  - `start(observingSystem: Bool = true)`: once; registers Defaults publishers
    (`dockBadgesEnabled`, `systemNotificationApps`) and NSWorkspace observers only when
    `observingSystem`; then `settingChanged()`.
  - `settingChanged()`: off or no chosen apps → cancel timer, clear summary, status `.off`
    (or `.ready` with empty summary when on but no apps); reader unavailable → `.unavailable`,
    no timer. Otherwise `refresh()`.
  - `refresh()`: guard enabled, not paused, reader available; `read(bundleIDs: apps)`;
    parse labels into badges (only for running chosen apps); publish summary only if it
    changed; status `.ready`; then cancel any pending tick and schedule the next one in
    3 s **only if** `result.running` is not empty. No chosen app running → no timer.
  - `appEvent(bundleID:)` for launch / quit / activate: if enabled, not paused and the
    bundle ID is chosen → `refresh()` now (on quit the app drops out of `running`, so its
    badge goes away).
  - `setPaused(sleeping:locked:)`: same flags as `SystemNotificationStore`; pausing cancels
    the timer; resuming calls `refresh()`.
  - Observers (real only): will/didSleep, screensDidSleep/Wake, session resign/become
    active, `com.apple.screenIsLocked/Unlocked`, `didLaunchApplication`,
    `didTerminateApplication`, `didActivateApplication` (bundle ID from
    `NSWorkspace.applicationUserInfoKey`).
  - `suggestedApps() -> [String]`: running regular apps; only called from Settings while
    it is open, result not stored.
- Idle cost: no timer when off, paused, or no chosen app running.

### `DockBadges/DockBadgeViews.swift`
- `DockBadgeCountCapsule(text:)` small capsule (same look as the banner count capsule).
- `DockBadgeLiveActivity`: closed-notch wing, same layout as `InboxLiveActivity`: icon of
  `summary.top` (via `SystemNotificationStore.shared.icon(for:)`) left, `totalText` right
  in white.
- `DockBadgeRowsView`: one row per badge (icon, app name, count capsule, click →
  `SystemNotificationStore.shared.open(bundleID:)`), used in the Notifications tab when
  there is no history.
- `DockBadgeSettingsRows`: switch "Show unread counts" plus status line
  (`.unavailable` → "Unread counts are not available on this macOS version").

## Edits to existing files

- `NubrixApp.swift`: `DockBadgeStore.shared.start()` next to `SystemNotificationStore.shared.start()`.
- `SystemNotificationViews.swift` (`SystemNotificationSettingsSection`):
  - `Defaults.Toggle(.dockBadgesEnabled) "Show unread counts"` right below the first switch.
  - App rows (and Refresh) shown when `enabled || badgesEnabled`; rows come from
    `DockBadgeAppList.rows(...)` with `suggestedApps()` taken on appear and when the badge
    switch turns on; each row shows its current count capsule.
  - `.noAccess` row: extra `Button("Use unread counts instead")` when the badge switch is off.
  - Footer: one added sentence about unread counts.
- `SystemNotificationStore.swift`: when notifications are turned off, only leave the
  Notifications tab if `dockBadgesEnabled` is also off.
- `SystemNotificationsTabView.swift`: chip shows a count capsule from `DockBadgeStore` for
  that app; when history is empty and badges exist → `DockBadgeRowsView`; when
  notifications are off but badges are on and nothing is badged → "No unread messages";
  `.noAccess` empty state gets the same "Use unread counts instead" button.
- `ContentView.swift`: `@ObservedObject dockBadges`; `dockBadgeWingShowing` = same guards as
  `inboxWingShowing` (closed, not hidden, no expanding view, keep-icon setting on, no
  banner, no needs-attention, no music, no meeting countdown) and `!inboxWingShowing` and
  `dockBadges.total > 0`; render `DockBadgeLiveActivity()` right after the inbox wing
  branch; tap → `coordinator.currentView = .notifications`.
- `TabSelectionView.swift`: bell dot falls back to the notice tint while the badge total > 0.
- `NotchTabLayout.swift` / `NotchTabSettings.swift`: Notifications tab enabled when
  `systemNotificationsEnabled || dockBadgesEnabled`; layout also listens to the new key.
- `NubrixInbox.swift`: unchanged (stays on `systemNotificationsEnabled`).

## Tests (`NubrixTests/DockBadges/`)

- `DockBadgeLabelTests`: `"3"`, `" 12 "`, `"99+"`, `"•"`, `"!"`, `""`, `"   "`, nil, `"0"`, long label cut.
- `DockBadgeSummaryTests`: total with numeric and dot badges, top by count, tie by chosen
  order, empty summary, `totalText` above 99.
- `DockBadgeAppListTests`: dedupe, ticked kept when not installed, defaults only when
  installed, own bundle ID removed, empty inputs.
- `DockBadgeStoreTests` (fake reader, fake scheduler, fake settings; no Defaults writes):
  - switch off → no read, no timer, status `.off`;
  - on, no chosen app running → one read, no timer;
  - on, chosen app running → badges published, timer scheduled; firing the timer reads again;
  - pause (sleep / lock) → timer cancelled, no reads on fire; resume → read + timer;
  - `appEvent` for a chosen app launching → read + timer; for an unchosen app → no read;
  - quit → badge removed, no timer when nothing chosen is running;
  - unchanged read → no `objectWillChange` emission; changed read → one emission;
  - reader unavailable → status `.unavailable`, no timer;
  - unticking an app → its badge is gone after `settingChanged()`.
- `DockBadgeReaderTests`: missing-symbol path is not crashable (`read` on an unavailable
  reader returns no labels); real reader: set `NSApp.dockTile.badgeLabel = "7"`, read
  `label(forPID: getpid())`, expect `"7"`; `XCTSkip` if the reader is unavailable or the
  label does not show up (hosted test app may not publish it); reset the label afterwards.

## Docs

- `ROADMAP.md`: move the item to done.
- `PERMISSIONS-AND-SETTINGS.md`: new switch, no permission, works only while the app runs.
- `PRIVACY-AND-SECURITY.md`: private LaunchServices SPI via `dlsym`, only ticked apps are
  polled, only the badge text, memory only; Settings looks at running apps' badges to
  suggest apps while it is open.

## On-device checks (user)

1. Settings → Notifications → Other apps → "Show unread counts" on, without Full Disk Access.
2. Get an unread message in WhatsApp, Slack, Mail, Messages; the Dock badge and the notch
   wing / tab rows should match within ~3 s. If one does not appear, run
   `lsappinfo info -only StatusLabel -app <bundle id>` to see whether LaunchServices has it.
3. Open the app → badge clears → wing disappears.
4. Quit the app → its count disappears.
5. Activity Monitor: Nubrix idle CPU stays ~0 % with no chosen app running.
6. With FDA on as well: banners still work, inbox unread count unchanged by badges.
