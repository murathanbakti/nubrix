# Permissions and settings

What Nubrix asks for, why, and where every switch lives. For an overview, see the [README](../../README.md#permissions).

## Permissions

Nubrix asks for nothing at launch. Each permission is asked the first time you use the feature that needs it. Onboarding is one screen of switches ("What do you want in your notch?"). It asks only for what you switch on there: Accessibility for Volume and brightness, Full Disk Access for Notifications from apps, and Bluetooth for Device and Mac alerts (asked once setup is done). Permissions you already granted keep working. Settings, Permissions shows the state of all of them (see below).

Version 0.1.1 and earlier asked for camera, calendar, Accessibility and Full Disk Access up front in onboarding. From 0.1.2 on, nothing is asked at launch.

| Permission | Why | When | Turn off in Settings |
|---|---|---|---|
| Calendars (full access) | Show upcoming events, meeting countdown, add events from the calendar sheet. Nubrix does not ask for Reminders access | When you click "Allow calendar access" in the calendar panel (click the date in the notch), Settings, Calendar. If access is off, it shows a button to System Settings, Privacy & Security, Calendars. The meeting countdown never asks on its own | Calendar, "Enable calendar" (also stops the meeting countdown) |
| Camera | Mirror preview. Nubrix only shows the live picture in the panel; it records, saves and sends nothing | The first time you open Mirror (the notch button or Control-Option-M), the panel explains why and asks when you click "Turn On Camera". If access is off, the panel has a button to System Settings, Privacy & Security, Camera. Nothing is asked while "Enable mirror" is off | Appearance, "Enable mirror" |
| Accessibility | Intercept volume and brightness keys to replace the system HUDs. macOS records the grant under "Nubrix", because the app is the responsible process. The helper `NubrixHelper` does the work (it is not sandboxed) but does not appear as its own entry | Settings, HUDs shows "Needs Accessibility" with a "Grant…" button (Settings, Permissions has the same button). "Replace system HUDs" turns on by itself once access is granted | HUDs, "Replace system HUDs" |
| Automation (Apple Events) | Control Spotify and Apple Music, and find the tab of a Claude session in Terminal, iTerm or Ghostty. These five are the only apps Nubrix is allowed to script | The default source, "Any app (Now Playing)", needs no Automation. If Now Playing does not work on your Mac, Nubrix uses Spotify when it is installed, otherwise Apple Music, and macOS then asks "Nubrix wants to control Spotify" or "Music" (Settings, Media can change the source). Terminal, iTerm or Ghostty is asked the first time you jump to a session tab | Media, "Enable media control"; Claude Code, "Open the session when you click it" |
| Screenshot folder | A folder picker; Nubrix keeps read-only access to the folder you choose | When you enable screenshots in Vitrin | Vitrin, "Capture screenshots" or "Enable Vitrin" |
| Paste from Other Apps (macOS 15.4 and later) | Lets Vitrin read what other apps copy. With the default or "Allow", Vitrin works as before. With "Ask", Vitrin does not read copied items in the background; it shows a pill with "Save Copied Item" (one read, macOS may show its alert) and "Allow in Settings…". With "Deny", it saves nothing | When Vitrin captures a copy and macOS is set to "Ask" | Vitrin, "Enable Vitrin" |
| Keychain | Stores the optional GitHub token | When you save a token | GitHub, "Enable GitHub integration" (the token stays in the Keychain but is not read) |
| Location (When In Use) | Show the names of Wi-Fi networks in the Controls tab (Wi-Fi). macOS treats network names as location data, so without it the tab still shows that you are connected and your IP address, but no names. Nubrix never reads your position and never asks for or stores Wi-Fi passwords: secured networks open Wi-Fi settings | Only when you tap "Show network names" in the Controls tab, Wi-Fi list, or Grant in Settings, Permissions. If you refused, the row opens System Settings, Privacy & Security, Location Services | Settings, Tabs (hide the Controls tab) |
| Bluetooth | Read the battery of AirPods, Beats and other Bluetooth devices | Once onboarding is done, when Device and Mac alerts is on (the default), or when you turn on "Battery of AirPods and other devices" | Everyday, "Battery of AirPods and other devices" |
| Full Disk Access | Read the macOS notification database to show other apps' notifications. Granted to Nubrix; the reading is done by the unsandboxed helper `NubrixHelper`, which only opens that one database, read-only. Nubrix shows a guide for granting it (see below) | Only if you turn on Settings, Notifications, Other apps, or click "Grant access…" | Notifications, "Show notifications from other apps" |

Turning a switch off stops the feature; it does not revoke a permission you already granted. To take a permission back, use System Settings, Privacy & Security.

Nubrix's own banners are drawn in the notch; it does not post to the macOS notification centre. Full Disk Access is only needed for notifications from other apps; everything else works without it. "Show unread counts" (Settings, Notifications, Other apps) needs no permission: it reads the number on the Dock icon of each ticked app while that app is open. There is no Screen Recording permission.

### Full Disk Access flow

"Grant access…" opens System Settings and a guide panel. After you turn Nubrix on, macOS offers "Quit & Reopen". Nubrix remembers where you started (the notch Notifications tab, Settings, Notifications or Settings, Permissions) for 30 minutes. After the restart it reopens that place with a short "Access granted" panel. If access is still off, it shows the guide again and does not reopen System Settings. Onboarding is marked as seen as soon as it appears, so quitting during onboarding never restarts it.

## Settings

Open Settings from the menu bar icon or, if enabled, the settings icon in the open notch. The sidebar groups the tabs; a tab for a feature starts with its "Enable …" switch, and that switch turns off the rest of the tab.

| Tab | What it controls |
|---|---|
| General | Menu bar icon, launch at login, displays, notch size and non-notch height, open on hover, haptics, gestures, battery indicator and power status notifications |
| Appearance | Accent color, settings icon in the notch, window shadow and corner radius, spectrogram and album-art options, idle face animation, mirror switch |
| Permissions | Live status for Accessibility, Full Disk Access, Camera, Calendar, Location, Automation (Music, Spotify, Terminal, iTerm, Ghostty) and Paste from Other Apps. Each row has a Grant or Open System Settings button. Status is read without asking. Automation status is only known while that app is running |

**Notch**

| Tab | What it controls |
|---|---|
| Tabs | Order of the notch tabs (drag and drop), which tabs are shown, always show tabs, remember last tab, Restore defaults |
| Notifications | Notification icon in the closed notch, inbox sources (Claude Code, notchctl, GitHub), notifications from other apps, unread counts from Dock badges, how notifications look (message text, grouping), Mark all as read |
| Everyday | Battery of AirPods and other devices, where sound plays, drives and memory cards, microphone and camera in use, internet connection. One switch each, all on by default |
| Vitrin | Capture toggles, screenshot folder and preview, retention, excluded apps, hide from screen sharing, clear history |
| Media | Media control switch, music source (Now Playing, Apple Music, Spotify, YouTube Music), live activity, lyrics, full screen behavior |
| Calendar | Calendar switch, calendar access, calendars shown in the notch, on the Home tab and in the calendar sheet, meeting countdown |
| Shelf | Shelf switch, drag behavior, quick share service |
| HUDs | Replace the system volume, display and keyboard-brightness HUDs (needs Accessibility for Nubrix) |

**Developer**

These three are off on a new install. Switch on "I write code" during onboarding, or each one here. Installs from before 0.3 keep what they had.

| Tab | What it controls |
|---|---|
| Claude Code | Claude Code integration switch, approving permissions from the notch, opening sessions, Home usage card, plan usage, and the hook installer command (built from where Nubrix is installed) with a Copy button |
| GitHub | GitHub integration switch, token, watched repositories, notification toggles |
| Dev | Dev tab switch (also notchctl), which localhost ports are watched, the notchctl install command |

**Other**

| Tab | What it controls |
|---|---|
| Shortcuts | Global keyboard shortcuts (defaults: Control-Option-V Vitrin, Control-Option-K calendar, Control-Option-M mirror) |
| Advanced | Window behavior (title bar, lock screen, screen recording) |
| About | Version, updates, credits and licenses |

### Notifications

The Notifications tab keeps these details out of the window:

- **Closed notch icon.** While something is unread, the closed notch keeps a small icon and count. When "Keep notification icon in the notch" is off, or when music is playing, the closed notch shows nothing; unread items are marked with a dot on their tab once you open the notch.
- **Sources.** Done, failed and needs-you events from Claude Code sessions, notifications sent with notchctl, and GitHub. Turning a source off also clears its unread items. A source is greyed out while its feature (Claude Code integration, Dev tab, GitHub integration) is off.
- **Other apps.** Only the apps you tick are read. The Notifications tab stacks notifications from the same conversation and keeps the last 50 in memory only: nothing is written to disk, logged or sent anywhere, and only notifications that arrive after you turn this on are shown. Tip: set an app's alert style to None in System Settings, Notifications to see its notifications only in the notch.
- **How they look.** Banners show as one line beside the notch. "Group in the notch": by conversation (default), by app, or off; "Start groups collapsed" shows the newest item of each group with "+N".
- **Unread counts.** "Show unread counts" reads the number on each ticked app's Dock icon instead: no permission needed, and it only works while that app is open.
- **Read state.** Items are marked read when you open the Claude, Dev or Notifications tab, or click the notification. They are not kept after a restart.
