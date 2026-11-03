# Research: jump to the exact tab in Ghostty and Warp

Date: 2026-11-03. Status: research only, no code changed.

## Recommendation

| Terminal | Method | What the hook sends | Permission | Where it runs | Fallback |
|---|---|---|---|---|---|
| Ghostty ≥ 1.4.0 | AppleScript: find `terminal` whose `tty` is `/dev/ttysNNN`, `focus` it, `activate` | existing `X-Nubrix-TTY` | Automation for Ghostty, asked on first click of a Ghostty row | App (add Ghostty to the Apple Events temporary exception) | match by `working directory` if exactly one terminal has it, else activate the app |
| Ghostty 1.3.x | AppleScript, match `working directory` (no `tty` yet) | session `cwd` (already known) | same as above | App | activate the app if 0 or more than 1 match |
| Ghostty < 1.3 | no scripting API | n/a | none | n/a | activate the app (today) |
| Warp (builds after 2026-05-22) | `NSWorkspace.open($WARP_FOCUS_URL)`, a `warp://session/<32 hex>` deep link that focuses the window, tab and pane | new header `X-Nubrix-Focus-URL` | none | App (opening a URL needs no entitlement) | activate the app if the variable is missing or opening fails |

Do not use Accessibility for either terminal (reasons below). Reuse the existing
`claudeOpenSession` switch: it already gates scripting Terminal and iTerm, prompts
only on first click, and is the documented switch for "Open the session when you
click it".

## How it works today

- Click paths: `AgentViews.swift:225` (`.onTapGesture { AgentSessionOpener.open(session.source) }`),
  `ContentView.swift:191-192`, `AgentPermissionStore.openInSourceApp(_:)` (line ~124).
- `Nubrix/Features/Agents/AgentSessionOpener.swift`
  - `isAllowed` = `Defaults[.claudeEnabled] && Defaults[.claudeOpenSession]`.
  - `canOpen(_:)` needs `source.activationBundleID` or a `termBundles` entry
    (only `Apple_Terminal` and `iTerm.app`).
  - `open(_:)`: (1) Claude desktop: `claude://code/continue?session=local_…` via
    `desktopURL(sessionID:)`; (2) if `source.tty` is set and the bundle is Terminal
    or iTerm, runs `tabScript(bundleID:tty:)` through `AppleScriptHelper.execute`
    (`Nubrix/helpers/AppleScriptHelper.swift`, `NSAppleScript` on a detached task)
    and falls back to `AgentAppActivator.activate` if it returns false or throws;
    (3) otherwise `AgentAppActivator.activate(bundleID:)` (`AgentAppActivator.swift`,
    `NSRunningApplication.activate()`).
- `Nubrix/Features/Agents/AgentModels.swift`, `struct AgentSourceInfo`: fields
  `entrypoint`, `appBundleID`, `terminal`, `hostSessionID`, `tty`; built from headers in
  `init(headers:)` (`x-nubrix-entrypoint`, `-app`, `-term`, `-host-session`, `-tty`);
  `merge(_:)`; `knownApps` already maps `com.mitchellh.ghostty` and
  `dev.warp.Warp-Stable` / `dev.warp.Warp`; `termPrograms` maps `ghostty` and `WarpTerminal`.
  Headers are read in `Nubrix/Features/Dev/AgentRoute.swift:91,99,113`.
- Hook `claude-plugin/scripts/nubrix-hook` (copied to `~/.config/nubrix/bin` by
  `scripts/install-hooks.sh`): `nubrix_source_args` sends `CLAUDE_CODE_ENTRYPOINT`,
  `__CFBundleIdentifier`, `TERM_PROGRAM`, `CLAUDE_CODE_HOST_SESSION_ID` on every event; on
  `SessionStart|UserPromptSubmit|Stop` it adds branch, remote and
  `X-Nubrix-TTY` from `ps -o tty= -p $$` (falling back to `$PPID`), validated as `ttys[0-9]{1,4}`.
  `claude-plugin/scripts/nubrix-permission` has its own `nubrix_source_args` (no TTY).
- Entitlements (`Nubrix/Nubrix.entitlements`, `Nubrix/Nubrix.release.entitlements`): sandboxed,
  `com.apple.security.automation.apple-events`, and
  `com.apple.security.temporary-exception.apple-events` = Spotify, Music,
  `com.apple.Terminal`, `com.googlecode.iterm2`. `NSAppleEventsUsageDescription` is in
  `Nubrix.xcodeproj/project.pbxproj` (lines ~1232, ~1286): "...bring the right Terminal or iTerm tab to the front."
- `NubrixHelper` is unsandboxed (`NubrixHelper/NubrixHelper.entitlements`), reached through
  `Nubrix/XPCHelperClient/XPCHelperClient.swift`; protocol in both
  `NubrixHelper/NubrixHelperProtocol.swift` and `Nubrix/XPCHelperClient/NubrixHelperProtocol.swift`.
  It already owns Accessibility for the HUDs.

## 1. Ghostty

- AppleScript arrived in 1.3.0 (2026-03-09), on by default, off with
  `macos-applescript = false`. Model: application > window > tab > terminal. Commands
  include `focus <terminal>` ("Focus a terminal, bringing its window to the front"),
  `select tab`, `activate window`, `input text`, `perform action`.
  1.3.1 changed `select tab` so it no longer activates the app, so the script should
  call `activate` itself.
- 1.4.0 (2026-10-27) adds read-only `pid` (foreground process) and `tty`
  (e.g. `/dev/ttys016`) on `terminal` and on the App Intents `TerminalEntity` (PR #11922).
  Raw codes: class `Gtrm`, property `Gtty`, `Gpid`, `Gwdr` (working directory).
- `terminal.id` is the surface view's `UUID.uuidString`. 1.4.0 also exports
  `GHOSTTY_SURFACE_ID` to the shell (PR #12027), a random non-zero 64-bit id. That is a
  different value and AppleScript does not expose it, so it cannot be used for matching today.
  Matching by `tty` is the reliable key: the hook's tty is the pty of the shell that runs `claude`,
  which equals Ghostty's `tty` for that split.
- Shell env from `src/termio/Exec.zig`: `TERM_PROGRAM=ghostty`, `TERM_PROGRAM_VERSION`,
  `GHOSTTY_RESOURCES_DIR`, `GHOSTTY_BIN_DIR`, `GHOSTTY_SHELL_FEATURES`, `TERM=xterm-ghostty`;
  1.4 adds `GHOSTTY_SURFACE_ID`. Bundle id `com.mitchellh.ghostty`.
- CLI: `ghostty +new-window`/`+new-tab` act on a running instance on GTK only; nothing focuses an
  existing surface. No URL scheme for focusing (proposed in discussion #10603, not shipped).
- App Intents / Shortcuts: a terminal entity with pid/tty exists, but Nubrix could only use it
  through a user-made Shortcut; not worth it.
- Proposed script (string-built like `tabScript`, tty already validated by regex):

  ```applescript
  tell application id "com.mitchellh.ghostty"
      repeat with t in terminals
          if tty of t is "/dev/ttys016" then
              focus t
              activate
              return true
          end if
      end repeat
  end tell
  return false
  ```

  On 1.3.x `tty` is unknown and raises an error; catch it (or check
  `version` first) and run a second script matching `working directory of t is "<cwd>"`
  that only focuses when exactly one terminal matches. Escape the cwd for AppleScript
  (backslash and quote) or pass it as a parameter via `NSAppleEventDescriptor` instead of
  string interpolation. Note that local Ghostty here is 1.2.3, so nothing above was run on
  this machine.
- Edge cases: Claude inside tmux/zellij (tty is the multiplexer's pty, no match → activate);
  `macos-applescript = false` (properties return empty → no match → activate); user
  declined Automation (error -1743 → activate, same as Terminal today).

## 2. Warp

- No AppleScript dictionary (`sdef` finds none) and no documented scripting API.
- Documented `warp://` actions only open things: `action/new_window?path=`,
  `action/new_tab?path=`, `launch/<path>`, `tab_config/<name>`, `drive/...`, `settings/...`.
  The docs say the scheme cannot "target or control an already-open tab or pane".
  Issue #8929 (open) asks for `warp://action/focus/tab?...`.
- But PR #11130 (merged 2026-05-22, "Expose terminal focus URL env vars") exports in
  every Warp session:
  - `WARP_TERMINAL_SESSION_UUID`: 32 lowercase hex chars
  - `WARP_FOCUS_URL`: `<channel scheme>://session/<uuid>` (e.g. `warp://session/…`,
    `warppreview://…`, `warposs://…`); opening it focuses the originating window, tab and pane
    via Warp's session deep-link handler (tested with `open "$WARP_FOCUS_URL"` across panes and windows).
  Undocumented in docs.warp.dev; a third-party tool says it shipped in v0.2026.05.27+. Older
  builds simply lack the variable.
- Other env: `TERM_PROGRAM=WarpTerminal`, `__CFBundleIdentifier` = `dev.warp.Warp-Stable`
  (Preview: `dev.warp.Warp-Preview`).
- Plan: the hook reads `WARP_FOCUS_URL`, validates
  `^warp[a-z]{0,12}://session/[0-9a-f]{32}$`, sends `X-Nubrix-Focus-URL`. The app re-validates,
  checks that `NSWorkspace.shared.urlForApplication(toOpen:)` is a `dev.warp.*` bundle, then
  `NSWorkspace.shared.open(url)`. No Apple Events, no TCC prompt, works sandboxed.
- Warp draws its UI itself (Rust/GPU); its AX tree does not expose tabs, so Accessibility is not a fallback.

## 3. Generic fallbacks (not recommended)

- Accessibility (`AXWindows`, `AXTabGroup`, title match): needs the Accessibility grant
  (helper has it only if the user enabled HUDs), titles are set by Claude Code and not
  unique, Ghostty native tabs are separate NSWindows in a tab group, Warp exposes nothing.
  It also can't pick a split.
- TTY → pid: `ps -o tty= -p $PPID` is already done; the hard part is mapping tty to a tab,
  which only the terminal can do (Ghostty `tty`, Terminal/iTerm `tty`).
- OSC title tagging (hook writes `ESC]2;nubrix-<id>BEL` to `/dev/ttysNNN`): would overwrite
  Claude Code's own title and write into the user's terminal from a background hook.
  Ghostty's read/write `name override` would be cleaner but still visible to the user. Skip.

## 4. Hook changes (cheap, no new processes)

- `claude-plugin/scripts/nubrix-hook`, inside the `SessionStart|UserPromptSubmit|Stop` branch:
  add `WARP_FOCUS_URL` (regex-checked, ≤ 64 chars) as `X-Nubrix-Focus-URL`. Optional:
  `TERM_PROGRAM_VERSION` as `X-Nubrix-Term-Version` to skip the Ghostty tty script on < 1.4
  (the app can also read Ghostty's `CFBundleShortVersionString` or just catch the error).
  `GHOSTTY_SURFACE_ID` is not needed until Ghostty can focus by it.
- Same header in `nubrix_source_args` of `claude-plugin/scripts/nubrix-permission` if the
  approval card's "open in source app" should jump for sessions not seen yet (it merges with the
  stored session, so this is optional).
- Re-run `scripts/install-hooks.sh` to refresh the copies in `~/.config/nubrix/bin`.

## 5. Files a later implementation touches

- `Nubrix/Features/Agents/AgentModels.swift`: `AgentSourceInfo` gains `focusURL`
  (validated in `init`), `init(headers:)` reads `x-nubrix-focus-url`, `merge(_:)`, `isEmpty`.
- `Nubrix/Features/Agents/AgentSessionOpener.swift`: `termBundles` add `ghostty` →
  `com.mitchellh.ghostty`, `WarpTerminal` → `dev.warp.Warp-Stable`; `open(_:)` tries
  `focusURL` (Warp) before the tty script; `tabScript(bundleID:tty:)` adds a Ghostty case plus
  the cwd fallback (needs the session cwd passed in, today only `AgentSourceInfo` is passed).
- `Nubrix/Nubrix.entitlements`, `Nubrix/Nubrix.release.entitlements`: add
  `com.mitchellh.ghostty` to `com.apple.security.temporary-exception.apple-events`
  (Warp needs nothing).
- `Nubrix.xcodeproj/project.pbxproj`: `INFOPLIST_KEY_NSAppleEventsUsageDescription` mention Ghostty.
- `Nubrix/Features/Inbox/InboxViews.swift` (~line 125): toggle text "Terminal and iTerm need
  Automation" → add Ghostty.
- Docs: `docs/nubrix/PERMISSIONS-AND-SETTINGS.md` (Automation row, line 14),
  `docs/nubrix/PRIVACY-AND-SECURITY.md`, `docs/nubrix/ROADMAP.md` (Phase 1 bullet).
- `claude-plugin/scripts/nubrix-hook` (and optionally `nubrix-permission`).

Sandbox note: running the Ghostty script in `NubrixHelper` would avoid widening the app's
temporary exception, but TCC attributes an embedded XPC service's Apple Events to Nubrix
anyway, so the prompt is the same and the code would split from the Terminal/iTerm path.
Keep it in the app like the existing scripts. Developer ID + hardened runtime already has
`com.apple.security.automation.apple-events`.

## Sources

- Ghostty AppleScript docs: https://ghostty.org/docs/features/applescript
- Ghostty sdef: https://github.com/ghostty-org/ghostty/blob/main/macos/Ghostty.sdef
- Ghostty `ScriptTerminal.swift` (id = UUID, tty, pid, focus): https://github.com/ghostty-org/ghostty/blob/main/macos/Sources/Features/AppleScript/ScriptTerminal.swift
- Ghostty 1.4.0 release notes: https://ghostty.org/docs/install/release-notes/1-4-0
- Ghostty 1.3.1 release notes: https://ghostty.org/docs/install/release-notes/1-3-1
- PR #11922 pid/tty: https://github.com/ghostty-org/ghostty/pull/11922
- PR #12027 GHOSTTY_SURFACE_ID: https://github.com/ghostty-org/ghostty/pull/12027
- Discussion #10603 (session id + focus URL idea): https://github.com/ghostty-org/ghostty/discussions/10603
- Ghostty env vars: https://github.com/ghostty-org/ghostty/blob/main/src/termio/Exec.zig
- Warp URI scheme: https://docs.warp.dev/features/uri-scheme
- Warp issue #8929 (focus tab request, WARP_FOCUS_URL workaround): https://github.com/warpdotdev/warp/issues/8929
- Warp PR #11130 (WARP_FOCUS_URL, WARP_TERMINAL_SESSION_UUID): https://github.com/warpdotdev/warp/pull/11130
