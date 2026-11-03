# Dock badge counts without Full Disk Access (research, 2026-11-03)

Roadmap item: "Later: Dock badge counts as a no-permission fallback"
(`docs/nubrix/ROADMAP.md`, "Notifications from other apps").

## Recommendation

Read each chosen app's badge from LaunchServices (the value `lsappinfo` prints as
`StatusLabel`) **in the sandboxed main app**, through the private
`_LSASNCreateWithPid` + `_LSCopyApplicationInformationItem(-2, asn, "StatusLabel")`
calls loaded with `dlsym`. No permission prompt, no helper round trip, no new
entitlement. Poll every 3 s only while at least one chosen app is running, paused
while asleep or locked, and re-read at once on app launch, quit and activation.
Make it its own switch ("Show unread counts"), offered as the one-click alternative
when Full Disk Access is missing. Keep the Accessibility route (Dock `AXStatusLabel`)
as an optional later extra in the helper, only for users who already granted
Accessibility for the HUDs.

Permission cost: none. Sandbox placement: main app (`Nubrix`), verified to work
under App Sandbox. Helper XPC protocol: unchanged.

## What was verified on this Mac (macOS 26.7.1, 25G241, read-only)

- `lsappinfo list` shows 119 apps; no app had a badge at the time
  (`StatusLabel` = `[ NULL ]` for WhatsApp, Teams, Chrome, Claude, Finder, Dock).
  Teams carries an empty `{ label = <null> }` dict (badge cleared, key kept).
- `lsappinfo info -only StatusLabel "WhatsApp"` prints nothing: WhatsApp's display
  name starts with U+200E (`"‎WhatsApp"`). Look up by bundle ID
  (`-app net.whatsapp.WhatsApp` or `lsappinfo find bundleid=…`), never by name.
- A throwaway test process set `NSApp.dockTile.badgeLabel = "7"`; then
  - `lsappinfo info -only StatusLabel <asn>` → `"StatusLabel"={ "label"="7" }`;
  - the private calls above returned `{ label = 7 }` both unsigned and from an
    ad-hoc signed **App Sandbox** bundle (`com.apple.security.app-sandbox` only),
    so a sandboxed app can read other apps' badges with no exception entitlement.
    (A sandboxed bare CLI tool traps on launch; it must be an app bundle, which
    Nubrix is.)
- Cost, in-process, 119 running apps: full scan (`_LSCopyRunningApplicationArray`
  + info for each) 2.6 ms; 4 chosen apps via `NSRunningApplication` + per-pid lookup
  0.5 ms (same sandboxed). At a 3 s interval that is ~0.02 % of one core; with the
  pid→ASN cached it drops further.
- Change notifications: `lsappinfo listen +all` during the badge set/clear showed
  launch/type/key-added events but **no event for `StatusLabel`**. The Dock gets
  badge changes some other way; there is no public or LS notification to subscribe
  to, so polling is required.
- `AXIsProcessTrusted()` is false for the terminal here, so the Dock AX route could
  not be exercised locally.
- Not verified (needs a real unread message): whether WhatsApp (a Mac Catalyst-style
  app, `UIDeviceFamily 6`) and apps that badge via
  `UNUserNotificationCenter.setBadgeCount` land in `StatusLabel`. First on-device
  check: with a visible badge, run
  `lsappinfo info -only StatusLabel -app net.whatsapp.WhatsApp` (also Mail
  `com.apple.mail`, Messages `com.apple.MobileSMS`, Slack `com.tinyspeck.slackmacgap`,
  Teams `com.microsoft.teams2`).

## 1. LaunchServices `StatusLabel`

- What it is: `NSDockTile.badgeLabel` is stored in the app's LaunchServices
  information as `StatusLabel = { label = "<text>" }`; the Dock draws from it.
  `lsappinfo` (in every macOS) reads it. simple-bar uses `lsappinfo` for its badge
  widget (10 s default refresh) and notes it only covers running apps.
- Permission: none (verified, sandboxed and not).
- From the helper: works too (helper is unsandboxed), but adds an XPC hop per poll for
  nothing; spawning `/usr/bin/lsappinfo` from the helper costs a process launch per
  poll (and the sandboxed app cannot spawn it). Use the in-process SPI.
- Private API: `_LSCopyRunningApplicationArray`, `_LSASNCreateWithPid`,
  `_LSCopyApplicationInformation`, `_LSCopyApplicationInformationItem` in
  CoreServices/LaunchServices, session `-2` (`kLSDefaultSessionID`). The key is the
  literal string `"StatusLabel"` (no exported constant needed). These have backed
  `lsappinfo` for many releases and work on 26.7.1; they are SPI, so wrap them:
  `dlsym` failure or an unexpected type → status `.unsupported`, feature hides itself.
  Nubrix ships Developer ID + notarized (not Mac App Store), and the helper already
  uses private frameworks (DisplayServices, CoreBrightness), so SPI use is consistent.
- Limits: running apps only (no ASN for a quit app); a value can lag the Dock when the
  Dock fails to redraw (Cursor forum, macOS 26.5.2: LS said NULL while the tile still
  showed 1 until `killall Dock`, i.e. LS is the truer value); label text can be
  non-numeric (`"•"`, `"99+"`, `"!"`) → show a dot or the raw text.

## 2. Accessibility on the Dock (`AXStatusLabel`)

- Each Dock item (`AXApplicationDockItem`) exposes the badge text as `AXStatusLabel`.
  Used by Doll (polls every 1 s, "<1 ms" per sync, needs Accessibility), Badgeify
  ("relies on the macOS Accessibility API"), the Raycast Dock Badges extension,
  alt-tab-macos, BetterCmdTab, Peninsula.
- Permission: Accessibility (Privacy & Security). In Nubrix that grant belongs to the
  unsandboxed helper `NubrixHelper` (used for the HUDs, see
  `PERMISSIONS-AND-SETTINGS.md`), so it would have to run in the helper via a new
  XPC method; the sandboxed app cannot use AX on other processes.
- Change notifications: BetterCmdTab notes the Dock "does not reliably post" an AX
  notification when `AXStatusLabel` changes, so it also polls. Same cost class as
  StatusLabel polling plus an XPC hop.
- Upside: reads exactly what the Dock shows, including any badge the Dock keeps for an
  app that is not running (not verified here). Downside: a permission prompt, the very
  thing this feature is meant to avoid, and it breaks if the Dock is restarted mid-read
  (rebuild the element tree on `com.apple.dock` relaunch).
- Verdict: not the default. Optional later: if the helper is already AX-trusted
  (`isAccessibilityAuthorized`), it could fill in counts for non-running Dock apps.

## 3. Notifications vs polling, CPU budget

- No usable push signal: LS sends nothing observable for `StatusLabel`; AX is
  unreliable; NSWorkspace and distributed notifications have no badge event.
- Use events to *gate* the poll, not replace it:
  `NSWorkspace.didLaunchApplicationNotification` / `didTerminateApplicationNotification`
  (start/stop when a chosen app appears/quits; drop its badge on quit),
  `didActivateApplicationNotification` (re-read now, apps usually clear the badge when
  opened), plus the sleep/wake/lock observers already in
  `SystemNotificationStore.registerObservers()`.
- Loop: 3 s with 25 % tolerance (same `Task.sleep(for:tolerance:)` style as
  `SystemNotificationStore.restartLoop()`), only while enabled, not paused, and at least
  one chosen app is running; otherwise no timer at all → idle 0 %. Publish only when a
  value changes so SwiftUI does not redraw.

## 4. UX

- Settings (`SystemNotificationSettingsSection`, "Other apps"): new switch "Show unread
  counts" with footer "Reads the badge number on each ticked app's Dock icon. No
  permission needed; works while the app is open." Independent of "Show notifications
  from other apps". In the `.noAccess` status row add a second button "Use unread
  counts instead", which turns the new switch on.
- App choice: share the existing ticked list `systemNotificationApps`. Without Full Disk
  Access `store.knownApps` is empty, so the row list also takes running regular apps and
  apps that have a badge right now (both cheap from the badge reader), plus a short
  default set (WhatsApp `net.whatsapp.WhatsApp` / `desktop.WhatsApp`, Messages, Mail,
  Slack, Teams, Telegram `ru.keepcoder.Telegram`, Discord `com.hnc.Discord`). Each row
  shows its current count.
- Closed notch: when there is no inbox wing (`inboxWingShowing` false) and the total is
  > 0, show a small wing in the same slot and priority: icon of the app with the highest
  count on the left, total on the right (same layout as `InboxLiveActivity`). Click opens
  the Notifications tab. Banners, music, meeting countdown and the inbox wing win. No
  banner on count change (no content to show; avoids noise).
- Notifications tab: filter chips get a count capsule (`chip(_:selected:action:)`); when
  history is empty (no FDA) show one row per badged app (icon, name, count, click →
  `store.open(bundleID:)`) instead of the empty state. Tab bell gets a dot while total > 0.
- With FDA working as well: both run; badges give the persistent "how many unread",
  banners/history give the content. Badges never feed `NubrixInbox` (they are not events),
  so there is no double counting.
- Privacy: only ticked apps are read, only the badge text, kept in memory.

## Repo changes (if built)

- New `Nubrix/Features/SystemNotifications/DockBadgeReader.swift`: `dlsym` wrapper for
  `_LSASNCreateWithPid` and `_LSCopyApplicationInformationItem`; `read(bundleIDs:) ->
  [String: String]`; status `.ok/.unsupported`.
- New `Nubrix/Features/SystemNotifications/DockBadgeStore.swift`: `@MainActor
  ObservableObject`, `@Published badges: [DockBadge]`, `total`, gated loop and NSWorkspace
  observers as above; `Defaults.publisher` on the new key like `SystemNotificationStore`.
- `SystemNotificationDefaults.swift`: `dockBadgesEnabled` (default `false`).
- `SystemNotificationModels.swift`: `struct DockBadge { bundleID, label, count: Int? }`.
- `SystemNotificationViews.swift`: switch, `.noAccess` button, row counts, row sources.
- `SystemNotificationsTabView.swift`: chip counts, badge rows when history is empty.
- `Nubrix/ContentView.swift` (`inboxWingShowing`, closed-notch slot near line 365, tab
  switch at line 454) and `Nubrix/Features/Inbox/InboxViews.swift` (new
  `DockBadgeLiveActivity` next to `InboxLiveActivity`).
- Notifications tab visible when `systemNotificationsEnabled || dockBadgesEnabled`:
  `Nubrix/Features/Tabs/NotchTabLayout.swift` (lines 61, 75),
  `Nubrix/Features/Tabs/NotchTabSettings.swift` (line 81).
  `NubrixInbox.swift` stays keyed on `systemNotificationsEnabled`.
- `Nubrix/components/Tabs/TabSelectionView.swift`: bell dot.
- `Nubrix/NubrixApp.swift` (~line 310): `DockBadgeStore.shared.start()`.
- Docs: `PERMISSIONS-AND-SETTINGS.md`, `PRIVACY-AND-SECURITY.md`, `ROADMAP.md`.
- No change to `NubrixHelper/` or `NubrixHelperProtocol` (AX extra would add
  `fetchDockBadges(allowedApps:with:)` later).

## Sources

- `man lsappinfo` (macOS 26.7.1): `info -only`, `listen`, notification codes.
- simple-bar notifications (uses `lsappinfo`, running apps only):
  https://www.jeantinland.com/toolbox/simple-bar/documentation/notifications/
- jao, application badges at the command line (`lsappinfo … StatusLabel`):
  https://jao.io/blog/application-badges-at-your-command-line.html
- Cursor forum, badge NULL in LS while Dock tile stale (macOS 26.5.2):
  https://forum.cursor.com/t/macos-dock-badge-stuck-at-1-after-update-os-badge-null-until-killall-dock/165949
- Doll (AX `AXStatusLabel`, 1 s poll, Accessibility): https://github.com/xiaogdgenuine/Doll
- Badgeify (Accessibility API): https://docs.badgeify.app/troubleshooting/missing-notification-counts
- Raycast Dock Badges: https://www.raycast.com/mrpunkin/dock-badges
- BetterCmdTab `DockBadgeObserver.swift` (no reliable AX change notification):
  https://github.com/rokartur/BetterCmdTab/blob/main/BetterCmdTab/System/DockBadgeObserver.swift
- Menu-Bar-Dock issue 11 (AppleScript `AXStatusLabel`):
  https://github.com/EthanSK/Menu-Bar-Dock/issues/11
- Apple DTS, `NSDockTile.badgeLabel`: https://developer.apple.com/forums/thread/798531
