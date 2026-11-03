# Plan: simpler Settings (2026-11-03)

Goal: fewer places to look, one pattern per tab, no dead controls. Only the UI moves; every `Defaults` key keeps its name and behavior.

## Sidebar

Built from `SettingsTab` (title, symbol, group), so the sidebar, the detail view, programmatic navigation and the "Turned off in Settings → …" hints share one source.

| Group | Tabs |
|---|---|
| (none) | General, Appearance, Permissions |
| Developer | Claude Code, GitHub, Dev |
| Notch | Tabs, Notifications, Vitrin, Media, Calendar, Shelf, HUDs |
| (none) | Shortcuts, Advanced, About |

`SettingsNavigation` moves to `Nubrix/components/Settings/` and takes a `SettingsTab`. A String overload stays only so `Features/Updates` keeps compiling untouched.

## Moves

- New Claude Code tab: master switch, notch approvals, open session, Home usage, plan usage, hook installer command with Copy, "How it works" link. The 190-word footer is cut to two sentences.
- Notifications keeps the notch icon, Sources, Other apps and Mark all as read. Long footers shrink to 1-2 sentences plus "Learn more".
- Meetings moves to Calendar. Calendar shows one access row.
- Battery moves into General. Mirror gets a section in Appearance. Accent color and window appearance move from Advanced to Appearance. "Always show tabs" and "Remember last tab" move to Tabs, which becomes a grouped Form.

## Removed

Dead controls and code: horizontal media gesture, custom music live activity and app icon placeholders, the four dead Calendar/Advanced toggles, unused declarations, commented-out Downloads, Extensions and Welcome code, the pointless Battery accessibility call. The `Defaults` keys they used stay declared.

## Pattern for every feature tab

1. Header-less section with the master toggle ("Enable ...") and a one-sentence footer.
2. The master disables the rest of the tab.
3. `Section { } header: { } footer: { }`, sentence case, American spelling.
4. `.settingsPage(tab)` sets the form style, tint and navigation title from `SettingsTab`.

## Steps

1. `SettingsTab`, `SettingsNavigation`, sidebar, hints, callers, tests.
2. Claude Code, Notifications, Calendar and Meetings.
3. General, Appearance, Tabs, Media, HUDs, Shelf, Advanced, Shortcuts, About.
4. GitHub, Dev, Vitrin copy and master switches.
5. Docs that name Settings paths.
