# Permissions and settings

What Nubrix asks for, why, and where every switch lives. For an overview, see the [README](../../README.md#permissions).

## Permissions

Nubrix asks for nothing at launch. Each permission is asked the first time you use the feature that needs it. Onboarding asks for nothing; it only lists which features will ask. Permissions you already granted keep working. Settings, Permissions shows the state of all of them (see below).

Version 0.1.1 still has the old onboarding, which asks for camera, calendar, Accessibility and Full Disk Access up front. The change described here ships in the next release.

| Permission | Why | When | Turn off in Settings |
|---|---|---|---|
| Calendars (full access) | Show upcoming events, meeting countdown, add events from the calendar sheet. Nubrix does not ask for Reminders access | When you click "Allow calendar access" in the calendar panel (click the date in the notch), Settings, Calendar or Settings, Meetings. If access is off, these show a button to System Settings, Privacy & Security, Calendars. The meeting countdown never asks on its own | Calendar, "Calendar" (also stops the meeting countdown) |
| Camera | Mirror preview. Nubrix only shows the live picture in the panel; it records, saves and sends nothing | The first time you open Mirror (the notch button or Control-Option-M), the panel explains why and asks when you click "Turn On Camera". If access is off, the panel has a button to System Settings, Privacy & Security, Camera. Nothing is asked while "Enable mirror" is off | Appearance, "Enable mirror" |
| Accessibility | Intercept volume and brightness keys to replace the system HUDs. macOS records the grant under "Nubrix", because the app is the responsible process. The helper `NubrixHelper` does the work (it is not sandboxed) but does not appear as its own entry | Settings, HUDs explains why and asks when you click "Allow Accessibility…" (or opens the pane with "Open Accessibility Settings"). "Replace system HUD" turns on by itself once access is granted | HUDs, "Replace system HUD" |
| Automation (Apple Events) | Control Spotify and Apple Music, and find the tab of a Claude session in Terminal or iTerm. These four are the only apps Nubrix is allowed to script | The Apple Music source is never chosen automatically. If Now Playing is unavailable on your macOS, Nubrix asks once which music source to use (Settings, Media can change it later). "Nubrix wants to control Music" or "Spotify" is asked only after you pick that source. Terminal or iTerm is asked the first time you jump to a session tab | Media, "Media control"; Notifications, "Open the session when you click it" |
| Screenshot folder | A folder picker; Nubrix keeps read-only access to the folder you choose | When you enable screenshots in Vitrin | Vitrin, "Capture screenshots" or "Enable Vitrin" |
| Paste from Other Apps (macOS 15.4 and later) | Lets Vitrin read what other apps copy. With the default or "Allow", Vitrin works as before. With "Ask", Vitrin does not read copied items in the background; it shows a pill with "Save Copied Item" (one read, macOS may show its alert) and "Allow in Settings…". With "Deny", it saves nothing | When Vitrin captures a copy and macOS is set to "Ask" | Vitrin, "Enable Vitrin" |
| Keychain | Stores the optional GitHub token | When you save a token | GitHub, "GitHub integration" (the token stays in the Keychain but is not read) |
| Full Disk Access | Read the macOS notification database to show other apps' notifications. Granted to Nubrix; the reading is done by the unsandboxed helper `NubrixHelper`, which only opens that one database, read-only. Nubrix shows a guide for granting it (see below) | Only if you turn on Settings, Notifications, Other apps, or click "Grant Access…" | Notifications, "Show notifications from other apps" |

Turning a switch off stops the feature; it does not revoke a permission you already granted. To take a permission back, use System Settings, Privacy & Security.

Nubrix's own banners are drawn in the notch; it does not post to the macOS notification centre. Full Disk Access is only needed for notifications from other apps; everything else works without it. There is no Screen Recording permission.

### Full Disk Access flow

"Grant Access…" opens System Settings and a guide panel. After you turn Nubrix on, macOS offers "Quit & Reopen". Nubrix remembers where you started (the notch Notifications tab, Settings, Notifications or Settings, Permissions) for 30 minutes. After the restart it reopens that place with a short "Access granted" panel. If access is still off, it shows the guide again and does not reopen System Settings. Onboarding is marked as seen as soon as it appears, so quitting during onboarding never restarts it.

## Settings

Open Settings from the menu bar icon or, if enabled, the settings icon in the open notch.

| Tab | What it controls |
|---|---|
| General | Menu bar icon, launch at login, displays, notch size and non-notch height, open on hover, gestures, haptics |
| Permissions | Live status for Accessibility, Full Disk Access, Camera, Calendar, Automation (Music, Spotify, Terminal, iTerm) and Paste from Other Apps. Each row has a Grant or Open System Settings button. Status is read without asking. Automation status is only known while that app is running |
| Appearance | Accent colour, settings icon in the notch, spectrogram and album-art options, custom Lottie visualizers, mirror switch and options |
| Tabs | Order of the notch tabs (drag and drop), which tabs are shown, Restore Defaults |
| Media | Media control switch, music source (Now Playing, Apple Music, Spotify, YouTube Music), lyrics, full screen behavior |
| Calendar | Calendar switch, calendar access, calendars shown in the notch, on the Home tab and in the calendar sheet |
| HUDs | Replace the system volume, display and keyboard-brightness HUDs (needs Accessibility for Nubrix) |
| Battery | Power and charging notifications in the notch |
| Shelf | File shelf behaviour |
| Vitrin | Capture toggles, screenshot folder and preview, retention, excluded apps, hide from screen sharing, clear history |
| Dev | Dev tab switch (also notchctl), which localhost ports are watched |
| GitHub | GitHub integration switch, token, watched repositories, notification toggles |
| Notifications | Inbox sources (Claude Code, notchctl, GitHub), notifications from other apps, Claude Code integration switch, opening sessions, notch approvals, plan usage, Home usage card, meeting countdown |
| Shortcuts | Global keyboard shortcuts (defaults: Control-Option-V Vitrin, Control-Option-K calendar, Control-Option-M mirror) |
| Advanced | Additional options |
| About | Version, credits and licenses |
