# Nubrix

Nubrix is a notch bar for macOS built for developers. It has music controls, volume and brightness HUDs and a file shelf, and adds three things on top: live status of your Claude Code sessions, a clipboard showcase called Vitrin, and a small toolbox for scripts and local dev servers.

Everything runs locally. There is no account, no cloud service and no telemetry.

> Nubrix is a personal project and open source under GPL-3.0 (see [Credits](#credits)). It is unsigned and has no release builds yet; see [Build from source](#build-from-source).

## Features

**Core notch features**
- Live music activity with playback controls and a visualizer
- Custom volume and brightness HUDs in the notch
- File shelf with drag and drop and quick share
- Calendar and reminders, mirror (camera preview)

**Claude Code sessions** (notch tab "Claude")
- Shows each Claude Code session as Working, Needs you, Failed, Done or Idle, fed by Claude Code hooks
- Works with the Claude Code CLI, the desktop app and the VS Code extension; each row shows where the session runs (Desktop, Terminal · iTerm, VS Code, Cursor, ...) and its git branch, and clicking a row brings that app to the front
- Context window bar and session cost per row, and your 5-hour usage limit in the tab header (needs the status line script)
- Approve or deny Claude Code permission requests from the notch (Allow / Deny, risky commands need a second click)

**Vitrin, a clipboard showcase** (notch tab "Vitrin", global shortcut Control-Option-V)
- Keeps copied images, text and links locally and shows them as cards
- Showcase panel under the notch with search, keyboard navigation (arrows, Enter to copy, P to pin, Delete to remove, Space for a large preview, Esc to close)
- Secret guard: text that looks like a credential (private keys, `sk-` keys, GitHub tokens, AWS keys, Slack tokens, JWTs, `Bearer` tokens, long high-entropy strings) is never stored; concealed, transient and password-manager pasteboard types are skipped
- Excluded apps: nothing copied while an excluded app is frontmost is stored (password managers and Keychain Access are excluded by default; the list is editable)
- Retention: history expires after a configurable period (default 30 days); pinned items never expire
- Per-type capture toggles for images, text and links

**Developer insights** (inside Vitrin)
- Detects JSON, code language (Swift, TypeScript/JavaScript, Python, Go, Rust, SQL, Shell, YAML, HTML, CSS), Base64, percent-encoded text, Unix timestamps, colors and UUIDs
- Cards show a badge and a lightweight syntax-highlighted preview
- Actions: copy pretty or minified JSON, copy decoded Base64 or URL text, copy ISO date, copy hex or rgb

**notchctl and the Dev tab**
- `notchctl` is a bash and curl CLI that shows a banner in the closed notch, for example `gh run watch && notchctl notify "CI green"`
- The "Dev" tab keeps the last notifications and shows which localhost ports (3000, 5173, 8080, 5432 and others, configurable) are listening; clicking an HTTP port opens it in the browser

## Screenshots

Screenshots will be added here.

## Requirements

- macOS 14 or later, Apple silicon or Intel
- Building from source needs Xcode 26

## Build from source

```sh
git clone <repository-url> nubrix
cd nubrix
xcodebuild -project Nubrix.xcodeproj -scheme Nubrix -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS' build
open build/Build/Products/Debug/Nubrix.app
```

The app is not signed with a Developer ID and not notarized. A local build is signed ad hoc, so it opens directly on the Mac that built it. If you copy a build to another Mac and Gatekeeper blocks it, right-click the app, choose Open, or remove the quarantine flag with `xattr -dr com.apple.quarantine Nubrix.app`. Each rebuild changes the ad hoc code identity, so macOS may ask again for permissions such as Accessibility or Camera.

## Claude Code hooks

Nubrix listens on a loopback HTTP server; the hook script forwards Claude Code hook events to it. Hooks are asynchronous, have a short timeout and always exit 0, so they never block or slow down Claude Code. If Nubrix is not running, the script does nothing.

**Option 1: the plugin**

```sh
claude --plugin-dir /path/to/nubrix/claude-plugin
```

The plugin in `claude-plugin/` registers the hook for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, PermissionDenied, Notification, Stop, StopFailure and SessionEnd.

**Option 2: manual hooks in `~/.claude/settings.json`**

Add the same hook under each event you want. Example for a few events (repeat the block for the others listed above):

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "/path/to/nubrix/claude-plugin/scripts/nubrix-hook", "async": true, "timeout": 5 } ] }
    ],
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "/path/to/nubrix/claude-plugin/scripts/nubrix-hook", "async": true, "timeout": 5 } ] }
    ],
    "PermissionRequest": [
      { "hooks": [ { "type": "command", "command": "/path/to/nubrix/claude-plugin/scripts/nubrix-hook", "async": true, "timeout": 5 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "/path/to/nubrix/claude-plugin/scripts/nubrix-hook", "async": true, "timeout": 5 } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "/path/to/nubrix/claude-plugin/scripts/nubrix-hook", "async": true, "timeout": 5 } ] }
    ]
  }
}
```

### Source label, branch and jump

The hook script sends the app that launched Claude Code (`CLAUDE_CODE_ENTRYPOINT`, `__CFBundleIdentifier`, `TERM_PROGRAM`) and, on SessionStart, UserPromptSubmit and Stop, the current git branch. Nothing else is read from your project.

### Context and usage meter (status line)

Claude Code passes context usage, cost and rate limits only to the status line command. `claude-plugin/scripts/nubrix-statusline` forwards that JSON to Nubrix in the background (it never delays the status line) and prints a compact line: `project · branch · model · ctx 42% · $1.23`. It works without `jq`; if `jq` is installed it is used for parsing. The plugin does not configure it; add it to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/nubrix/claude-plugin/scripts/nubrix-statusline"
  }
}
```

The context bar is green below 60%, orange up to 85% and red above. When a session crosses 85% Nubrix shows a banner and an inbox entry ("Context 87% - consider /compact"). The 5-hour limit appears in the Claude tab header when Claude Code reports it (claude.ai Pro, Max and Ultra subscribers, after the first response). If you already use a status line, call `nubrix-statusline` from it, or pipe its input to both.

### Approving permissions from the notch

`claude-plugin/scripts/nubrix-permission` is a synchronous `PermissionRequest` hook (the async `nubrix-hook` stays for state). It sends the request to Nubrix and waits for your answer; Nubrix shows the tool and the full command, file or URL with Allow and Deny, and the script turns the answer into the documented `hookSpecificOutput` decision. Rules:

- Nothing is ever approved automatically. If Nubrix is not running, the toggle is off, no answer arrives in time, or anything is malformed, the script prints nothing and Claude Code asks in its own dialog as before.
- Risky input (`rm -rf`, `sudo`, `git push --force`, `git reset --hard`, `curl | sh`, writes outside the project or to sensitive files, ...) is shown in red and needs a second click ("Allow anyway").
- "Open in <app>" brings the source app forward and withdraws the notch prompt so you answer natively. Answering in Claude Code first also withdraws the prompt.
- Up to 5 requests queue ("1 of 3"); requests over 64 KB or beyond the queue are left to Claude Code.
- Wait time: 110 s in the desktop app and VS Code (Claude Code shows its own dialog at the same time and whichever answers first wins), 25 s in a terminal (the hook may hold the terminal dialog back while it waits). Override with `NUBRIX_PERMISSION_WAIT` (seconds).
- Turn it off in Settings, Notifications, "Claude Code approvals".

Manual setup: in `~/.claude/settings.json`, add a second hook next to the existing async one under `PermissionRequest`:

```json
"PermissionRequest": [
  { "hooks": [
    { "type": "command", "command": "/path/to/nubrix/claude-plugin/scripts/nubrix-hook", "async": true, "timeout": 5 },
    { "type": "command", "command": "/path/to/nubrix/claude-plugin/scripts/nubrix-permission", "timeout": 125 }
  ] }
]
```

## notchctl

```sh
mkdir -p ~/.local/bin && ln -sf "$PWD/cli/notchctl" ~/.local/bin/notchctl
notchctl notify "Build done" --title api --style success
notchctl ping
```

See [cli/README.md](cli/README.md) for styles, duration and more examples.

## Privacy and security

- Everything stays on your Mac. Nubrix has no analytics and sends nothing to a Nubrix server. (Inherited features such as lyrics lookup or the YouTube Music controller make their own network requests when you use them.)
- The event server binds to the loopback interface only (127.0.0.1) on a random port and requires a random bearer token. Port and token are written to `~/.config/nubrix/agent-endpoint` with mode 0600 in a 0700 directory.
- Vitrin history is a SQLite database with image files beside it, stored in the app container (`~/Library/Containers/dev.nubrix.app/Data/Library/Application Support/Nubrix/Vitrin`) with 0600/0700 permissions. It is not encrypted yet.
- The secret guard is a heuristic. It reduces the chance of storing a credential but cannot catch everything; use excluded apps and the capture toggles, and clear the history from Settings, Vitrin when needed.
- The app is sandboxed. The Sparkle auto-updater is intentionally not started and no update feed is configured.

See [SECURITY.md](SECURITY.md) for reporting problems.

## Roadmap

See [docs/nubrix/ROADMAP.md](docs/nubrix/ROADMAP.md).

## Credits

- [boring.notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam, the project Nubrix is forked from (GPL-3.0)
- Ideas and selected logic for Vitrin from ClipBoardLine (MIT) and Tendedero (MIT)
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause)
- Other dependencies and their licenses are listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES)

## License

GNU General Public License v3.0, see [LICENSE](LICENSE).
