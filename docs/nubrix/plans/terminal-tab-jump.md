# Plan: jump to the exact tab in Ghostty and Warp

Date: 2026-11-03. Based on `docs/nubrix/research/terminal-tab-jump.md`.

Goal: clicking a Claude Code session row (or the closed-notch banner, or "Open" on a
permission card) focuses the Ghostty or Warp window, tab and split the CLI session runs in.
Terminal and iTerm keep their current tty match. Everything stays behind the existing
`claudeOpenSession` switch ("Open the session when you click it").

## Order of attempts in `AgentSessionOpener.open`

1. Claude desktop: `claude://code/continue?session=local_…` (unchanged).
2. Warp (`appBundleID` starts with `dev.warp.` or `terminal == "WarpTerminal"`): if the
   source has a valid `focusURL` and the app that handles that URL has a bundle id starting
   with `dev.warp.`, `NSWorkspace.shared.open(url)`. Otherwise activate Warp.
3. AppleScript, only when the target app is running:
   - Terminal, iTerm: tty match, as today.
   - Ghostty: strategy from the running app's `CFBundleShortVersionString`
     (`NSRunningApplication.bundleURL` → `Bundle(url:)`):
     - ≥ 1.4 or unknown/unparseable: tty match, then working-directory match if exactly one
       terminal has the session's cwd.
     - 1.3.x: working-directory match only (exactly one match).
     - < 1.3: no script.
   - Script returns `false` or throws (Automation denied, `macos-applescript = false`,
     tmux, no match) → activate the app.
4. Activate the app (today's behaviour).

Nubrix never launches a terminal that is not running.

## Files and symbols

### New: `Nubrix/Features/Agents/AgentTerminalFocus.swift`

Pure, testable logic plus the AppleScript handler runner.

- `enum AgentTerminalFocus`
  - bundle ids: `terminal = "com.apple.Terminal"`, `iTerm = "com.googlecode.iterm2"`,
    `ghostty = "com.mitchellh.ghostty"`, `warpStable = "dev.warp.Warp-Stable"`.
  - `termBundles: [String: String]`: `Apple_Terminal`, `iTerm.app`, `ghostty`, `WarpTerminal`.
  - `static func bundleID(for source: AgentSourceInfo) -> String?`
    (`source.activationBundleID ?? termBundles[source.terminal]`).
  - `static func isWarp(bundleID: String?, terminal: String) -> Bool`.
  - `static func isWarpHandler(bundleID: String?) -> Bool`: `hasPrefix("dev.warp.")`.
  - `static func ttyDevice(_ tty: String) -> String?`: `"/dev/" + tty`, returned only if it
    matches `^/dev/ttys[0-9]{1,4}$`.
  - `static func directory(_ cwd: String?) -> String?`: absolute path (`/` prefix), ≤ 1024,
    no control characters; else nil.
  - `enum GhosttySupport { case ttyAndDirectory, directoryOnly, none }` and
    `static func ghosttySupport(version: String?) -> GhosttySupport` (parse leading
    `major.minor` integers; nil or garbage → `.ttyAndDirectory`).
  - `struct Script: Equatable { bundleID, source, handler: String?, arguments: [String] }`.
  - `enum Strategy: Equatable { case desktop(URL), warp(URL), script(Script), activate }`.
  - `static func strategy(source:cwd:ghosttyVersion:) -> Strategy`: no runtime checks
    (running apps, URL handler) so it can be unit tested.
  - `static func terminalScript(device:)`, `iTermScript(device:)`: today's `tabScript`
    bodies, moved here. The device is the only interpolated value and is regex-checked.
  - `static let ghosttySource: String`: a constant script with handler
    `nubrix_focus(targetTTY, targetDir)`. tty and cwd are passed as Apple Event parameters,
    never interpolated. Returns `true`/`false`. tty lookup in a `try` so 1.3.x falls
    through to the directory match; the directory match only focuses when exactly one
    terminal matches. Calls `focus` then `activate`.
  - `static func subroutineEvent(handler:arguments:) -> NSAppleEventDescriptor`:
    `kASAppleScriptSuite`/`kASSubroutineEvent`, `keyASSubroutineName` = lowercased handler,
    `keyDirectObject` = list of string descriptors.
  - `static func run(_ script: Script) async throws -> Bool`: on a detached task; plain
    `NSAppleScript.executeAndReturnError` when `handler == nil`, else
    `compileAndReturnError` + `executeAppleEvent(_:error:)`.
- `AgentDesktopURL` logic (`desktopURL(sessionID:)`) moves into the same enum so
  `strategy` can return `.desktop`.

### `Nubrix/Features/Agents/AgentModels.swift` (`AgentSourceInfo`)

- New field `focusURL: String`, accepted only if it matches
  `^warp[a-z]{0,12}://session/[0-9a-f]{32}$` (≤ 64 chars, checked before the regex).
- `init(..., focusURL:)`, `init(headers:)` reads `x-nubrix-focus-url`, `merge(_:)`,
  `isEmpty` include it.

### `Nubrix/Features/Agents/AgentSessionOpener.swift`

- `canOpen` uses `AgentTerminalFocus.bundleID(for:)`.
- `open(_ source: AgentSourceInfo, cwd: String? = nil)`: compute the Ghostty version only
  when the bundle is Ghostty, call `strategy`, then do the runtime checks above and fall
  back to `AgentAppActivator.activate`.
- Call sites pass the cwd: `AgentViews.swift` row (`session.cwd`), `ContentView.swift`
  banner (`session.cwd`), `AgentPermissionStore.openInSourceApp`
  (`session?.cwd ?? prompt.payload.cwd`).

### Hook: `claude-plugin/scripts/nubrix-hook`

In the `SessionStart|UserPromptSubmit|Stop` branch, after the TTY header:

```bash
focus_url="${WARP_FOCUS_URL:-}"
if [ "${#focus_url}" -le 64 ] && [[ "$focus_url" =~ ^warp[a-z]{0,12}://session/[0-9a-f]{32}$ ]]; then
  source_args+=(-H "X-Nubrix-Focus-URL: $focus_url")
fi
```

`LC_ALL=C` is already set, so the ranges are ASCII. `nubrix-permission` is not changed: the
approval card merges with the stored session, which already has the URL after
`SessionStart`. No `X-Nubrix-Term-Version` header: the app reads the running Ghostty's
version, which is what decides the AppleScript dictionary.

### Entitlements, usage string, toggle

- `Nubrix/Nubrix.entitlements`, `Nubrix/Nubrix.release.entitlements`: add
  `com.mitchellh.ghostty` to `com.apple.security.temporary-exception.apple-events`.
  Warp needs nothing (opening a URL).
- `Nubrix.xcodeproj/project.pbxproj` (both configs): "Nubrix uses Apple Events to control
  music apps and to bring the right Terminal, iTerm or Ghostty tab to the front."
- `Nubrix/Features/Inbox/InboxViews.swift`: "Open the session when you click it
  (Terminal, iTerm and Ghostty need Automation)".

### Docs

- `PERMISSIONS-AND-SETTINGS.md`: Automation row names Ghostty (five scriptable apps).
- `PRIVACY-AND-SECURITY.md`: the hook also sends Warp's `WARP_FOCUS_URL` (validated).
- `CLAUDE-CODE.md`: Ghostty and Warp bullets (what happens, versions, fallbacks).
- `ROADMAP.md`: Phase 1 bullet "click a row to focus the exact tab (Terminal, iTerm,
  Ghostty ≥ 1.3, Warp)", not yet tried on device.

## Tests

`NubrixTests/TabJump/` (`@testable import Nubrix`):

- `AgentSourceInfoFocusURLTests`: valid header parsed; rejected: uppercase hex, 31/33 hex,
  `https://session/…`, extra path, query, CR/LF injection, 13-letter scheme suffix,
  leading/trailing space, empty; `merge` and `isEmpty`.
- `AgentTerminalFocusValidationTests`: `ttyDevice` accepts `ttys016`, rejects `ttys`,
  `tty016`, `ttys1;`, quote/`do shell script` payloads, 5 digits; `directory` rejects
  relative and control characters; `isWarpHandler` rejects `dev.warpx.x`, `com.evil.dev.warp.`.
- `AgentTerminalFocusStrategyTests`: Terminal and iTerm with tty → script with device;
  without tty → activate; Ghostty 1.4/1.5/2.0/unknown → `[device, cwd]`; 1.3.x →
  `["", cwd]`; 1.2 → activate; Ghostty with neither tty nor cwd → activate; bundle from
  `TERM_PROGRAM` when `appBundleID` is empty; Warp with URL → `.warp`, without → activate;
  desktop → `.desktop`.
- `AgentTerminalFocusScriptTests`: Ghostty source is constant (no argument text in it);
  Terminal/iTerm sources contain the device and nothing else from the input; subroutine event has
  the lowercased handler name and the arguments in order; running a local handler
  (`on nubrix_echo(a, b)` with no `tell`) through `run` returns injection strings
  verbatim, proving parameters are not evaluated.

Hook: `scripts/test-hook-headers.sh` runs `nubrix-hook` in dev mode
(`NUBRIX_DEV=1`, `NUBRIX_ENDPOINT_FILE` in a temp dir) against a one-shot `nc` listener and
checks that `X-Nubrix-Focus-URL` is sent for a valid URL and absent for invalid ones.

## Needs on-device verification

- Ghostty 1.4: first click shows the Automation prompt for Ghostty; the right window, tab
  and split come to the front; denying it falls back to activating Ghostty.
- Ghostty 1.3.x: cwd fallback; two sessions in the same folder only activate.
- Warp build with `WARP_FOCUS_URL` (v0.2026.05.27+): pane focus across windows; older Warp
  only activates.
- Sandbox: reading Ghostty's `Info.plist` and the Warp URL handler's bundle id from the
  sandboxed app.
- Claude inside tmux/zellij in Ghostty: activates only.
- Hooks must be reinstalled (`scripts/install-hooks.sh`, by the user) to send the new header.

## Risks

- Ghostty's scripting dictionary might differ from the docs (`terminals`, `tty`,
  `working directory`, `focus`); errors fall back to activation.
- `WARP_FOCUS_URL` is undocumented and may change format; a stricter regex then only
  disables the jump.
- Working-directory compare is exact; symlinked or trailing-slash paths won't match.
