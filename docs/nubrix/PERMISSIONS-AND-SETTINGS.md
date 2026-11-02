# Permissions and settings

What Nubrix asks for, why, and where every switch lives. For an overview, see the [README](../../README.md#permissions).

## Permissions

Nubrix asks for access only when you use the feature that needs it (the onboarding screen also offers the ones marked with an asterisk, and every onboarding step can be skipped):

| Permission | Why | When | Turn off in Settings |
|---|---|---|---|
| Calendars (full access)* | Show upcoming events, meeting countdown, add events from the calendar sheet. Nubrix does not ask for Reminders access | When you click Allow in onboarding, Settings, Calendar or the calendar sheet | Calendar, "Calendar" (also stops the meeting countdown) |
| Camera | Mirror preview. Nubrix only shows the live picture in the panel; it records, saves and sends nothing | The first time you open Mirror (the notch button or Control-Option-M), the panel explains why and asks when you click "Turn On Camera". If access is off, the panel has a button to System Settings, Privacy & Security, Camera. Nothing is asked while "Enable mirror" is off, and onboarding does not ask | Appearance, "Enable mirror" |
| Accessibility* | Intercept volume and brightness keys to replace the system HUDs. Granted to the helper process `NubrixHelper`, which is not sandboxed | Only if you turn on "Replace system HUD" | HUDs, "Replace system HUD" |
| Automation (Apple Events) | Control Spotify and Apple Music, and find the tab of a Claude session in Terminal or iTerm. These four are the only apps Nubrix is allowed to script | When you pick those sources in Settings, Media, or first click a Terminal or iTerm session | Media, "Media control"; Notifications, "Open the session when you click it" |
| Screenshot folder | A folder picker; Nubrix keeps read-only access to the folder you choose | When you enable screenshots in Vitrin | Vitrin, "Capture screenshots" or "Enable Vitrin" |
| Pasteboard access | On recent macOS versions macOS may ask whether Nubrix may read what other apps copy. Vitrin cannot capture anything while access is denied | When Vitrin starts capturing | Vitrin, "Enable Vitrin" |
| Keychain | Stores the optional GitHub token | When you save a token | GitHub, "GitHub integration" (the token stays in the Keychain but is not read) |
| Full Disk Access* | Read the macOS notification database to show other apps' notifications. Granted to Nubrix; the reading is done by the unsandboxed helper `NubrixHelper`, which only opens that one database, read-only. Nubrix shows a guide for granting it | Only if you turn on Settings, Notifications, Other apps | Notifications, "Show notifications from other apps" |

Turning a switch off stops the feature; it does not revoke a permission you already granted. To take a permission back, use System Settings, Privacy & Security.

Nubrix's own banners are drawn in the notch; it does not post to the macOS notification centre. Full Disk Access is only needed for notifications from other apps; everything else works without it. There is no Screen Recording permission.

## Settings

Open Settings from the menu bar icon or, if enabled, the settings icon in the open notch.

| Tab | What it controls |
|---|---|
| General | Menu bar icon, launch at login, displays, notch size and non-notch height, open on hover, gestures, haptics |
| Appearance | Accent colour, settings icon in the notch, spectrogram and album-art options, custom Lottie visualizers, mirror switch and options |
| Tabs | Order of the notch tabs (drag and drop), which tabs are shown, Restore Defaults |
| Media | Media control switch, music source (Now Playing, Apple Music, Spotify, YouTube Music), lyrics, full screen behavior |
| Calendar | Calendar switch, calendar access, calendars shown in the notch, on the Home tab and in the calendar sheet |
| HUDs | Replace the system volume, display and keyboard-brightness HUDs (needs Accessibility) |
| Battery | Power and charging notifications in the notch |
| Shelf | File shelf behaviour |
| Vitrin | Capture toggles, screenshot folder and preview, retention, excluded apps, hide from screen sharing, clear history |
| Dev | Dev tab switch (also notchctl), which localhost ports are watched |
| GitHub | GitHub integration switch, token, watched repositories, notification toggles |
| Notifications | Inbox sources (Claude Code, notchctl, GitHub), notifications from other apps, Claude Code integration switch, opening sessions, notch approvals, plan usage, Home usage card, meeting countdown |
| Shortcuts | Global keyboard shortcuts (defaults: Control-Option-V Vitrin, Control-Option-K calendar, Control-Option-M mirror) |
| Advanced | Additional options |
| About | Version, credits and licenses |
