# Nubrix

Nubrix is a notch bar for macOS built for developers. It keeps the music, HUD and file shelf you know from [boring.notch](https://github.com/TheBoredTeam/boring.notch) and adds three things on top: live status of your Claude Code sessions, a clipboard showcase called Vitrin, and a small toolbox for scripts and local dev servers.

Everything runs locally. There is no account, no cloud service and no telemetry.

> Nubrix is a personal project and a fork of boring.notch (GPL-3.0). It is unsigned and has no release builds yet; see [Build from source](#build-from-source).

## Features

**Inherited from boring.notch**
- Live music activity with playback controls and a visualizer
- Custom volume and brightness HUDs in the notch
- File shelf with drag and drop and quick share
- Calendar and reminders, mirror (camera preview)

**Claude Code sessions** (notch tab "Claude")
- Shows each Claude Code session as Working, Needs you, Failed, Done or Idle, fed by Claude Code hooks
- Works with the Claude Code CLI and the desktop app

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
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS' build
open build/Build/Products/Debug/Nubrix.app
```

(The Xcode project, scheme and target keep the upstream name `boringNotch` so upstream changes stay easy to merge; the product is `Nubrix.app`.)

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

## notchctl

```sh
mkdir -p ~/.local/bin && ln -sf "$PWD/cli/notchctl" ~/.local/bin/notchctl
notchctl notify "Build done" --title api --style success
notchctl ping
```

See [cli/README.md](cli/README.md) for styles, duration and more examples.

## Privacy and security

- Everything stays on your Mac. Nubrix has no analytics and sends nothing to a Nubrix server. (Inherited boring.notch features such as lyrics lookup or the YouTube Music controller make their own network requests when you use them.)
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
