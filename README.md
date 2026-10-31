# Nubrix

Nubrix is a notch bar for macOS built for developers. It has music controls, volume and brightness HUDs and a file shelf, and adds three things on top: live status of your Claude Code sessions, a clipboard showcase called Vitrin, and a small toolbox for scripts and local dev servers.

Everything runs locally. There is no account, no cloud service, no telemetry and no auto-updater. The few optional network uses are listed under [Privacy and security](#privacy-and-security).

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
- Approve or deny Claude Code permission requests from the notch (Allow / Deny; Allow needs a real mouse click and risky requests need a second click; requires the sealed hook scripts, see [Claude Code hooks](#claude-code-hooks))

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

**GitHub** (inside the Dev tab and on Claude session rows)
- The Dev tab has a GitHub, Servers and Notifications switch. GitHub shows three columns: PRs where your review is requested, your open PRs (CI checks, review decision, merge conflicts, draft) and recent GitHub Actions runs of your watched repositories
- A closed-notch banner and a notification entry appear for a new review request, your PR's CI turning red or green, a merge conflict, and a failed workflow run on a default branch, on your PR branches, on your Claude session branches or started by you
- Each Claude session row shows the PR of its branch as a small chip (`#123` with a CI mark); click it to open the PR
- Read-only: Nubrix never writes to GitHub. See [GitHub integration](#github-integration)

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

**Install a Release build.** `scripts/install-local.sh [--open]` builds Release into `~/Library/Caches/Nubrix/DerivedData`, verifies the bundle (hardened runtime on, no `get-task-allow`, only `NubrixHelper.xpc` and only the Lottie and MediaRemoteAdapter frameworks), quits a running Nubrix, installs `Nubrix.app` to `/Applications` and then runs `scripts/install-hooks.sh`. With `--open` it starts the app afterwards. It stops if a check fails.

The app is not signed with a Developer ID and not notarized. A local build is signed ad hoc, so it opens directly on the Mac that built it. If you copy a build to another Mac and Gatekeeper blocks it, right-click the app, choose Open, or remove the quarantine flag with `xattr -dr com.apple.quarantine Nubrix.app`. Each rebuild changes the ad hoc code identity, so macOS may ask again for permissions such as Accessibility or Camera. Nubrix has no auto-updater; to update, pull and build again. This is version 0.1.0.

## Claude Code hooks

Nubrix listens on a loopback HTTP server; the hook script forwards Claude Code hook events to it. Hooks are asynchronous, have a short timeout and always exit 0, so they never block or slow down Claude Code. If Nubrix is not running, the script does nothing.

**Install the sealed scripts (recommended, required for notch approvals).** Hooks run with your full privileges in every Claude Code session, so they must not live in a folder that Claude, a `git checkout` or a pull request can rewrite:

```sh
scripts/install-hooks.sh
```

(`scripts/install-local.sh` runs it for you, see [Build from source](#build-from-source).) It copies `nubrix-hook`, `nubrix-permission`, `nubrix-statusline` and `notchctl` to `~/.config/nubrix/bin/` (directory mode 0700, files 0500), can be run again at any time, and prints the exact `settings.json` snippet to paste. It never edits `~/.claude/settings.json`. Re-run it after updating Nubrix, and it warns if your settings still point into a checkout.

- **Two folders, two jobs.** `~/.config/nubrix/` holds the sealed scripts; the sandboxed app can only read it. `~/.config/nubrix-run/` holds `agent-endpoint` (`port token pid`, file 0600 in a 0700 directory) and is the only place under `~/.config` the app can write. So the app cannot modify the scripts Claude Code runs.
- **Deny rules.** The snippet also adds `permissions.deny` rules so Claude cannot edit the scripts or read the token: `Edit` and `Write` for `~/.config/nubrix/**` and `~/.config/nubrix-run/**`, and `Read(~/.config/nubrix-run/**)`.
- **What the scripts check.** They pin `PATH` to the system directories and call every tool by absolute path. Before sending the token they check that the process id in the endpoint file is a running `Nubrix.app` owned by you, and ignore the file otherwise. The permission hook additionally checks with `lsof` that this process is the one listening on the port, and verifies a reply proof (see [Approving permissions from the notch](#approving-permissions-from-the-notch)).
- `NUBRIX_ENDPOINT_FILE` and `NUBRIX_PERMISSION_WAIT` are only honoured when `NUBRIX_DEV=1` is set (tests); a project's `.claude/settings.json` cannot redirect the hooks.
- Large `tool_response` and file contents are stripped by `nubrix-hook` before forwarding (with the system `jq`; without it, events over 256 KB are reduced to session, tool and event name).

**Manual hooks in `~/.claude/settings.json`.** Use the snippet `install-hooks.sh` prints, or add the hook by hand under each event you want, always with the sealed copies (`~/.config/nubrix/bin/...`, written out as the absolute paths the script prints), never a git checkout. Example for a few events (repeat the block for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, PermissionDenied, Notification, Stop, StopFailure and SessionEnd):

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "~/.config/nubrix/bin/nubrix-hook", "async": true, "timeout": 5 } ] }
    ],
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "~/.config/nubrix/bin/nubrix-hook", "async": true, "timeout": 5 } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/.config/nubrix/bin/nubrix-hook", "async": true, "timeout": 5 } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "~/.config/nubrix/bin/nubrix-hook", "async": true, "timeout": 5 } ] }
    ]
  },
  "permissions": {
    "deny": [
      "Edit(~/.config/nubrix/**)", "Write(~/.config/nubrix/**)",
      "Edit(~/.config/nubrix-run/**)", "Write(~/.config/nubrix-run/**)",
      "Read(~/.config/nubrix-run/**)"
    ]
  }
}
```

The `PermissionRequest` entry that enables notch approvals is shown under [Approving permissions from the notch](#approving-permissions-from-the-notch).

**Plugin (status only).** For a quick look without touching your settings you can load the plugin:

```sh
claude --plugin-dir /path/to/nubrix/claude-plugin
```

It registers `nubrix-hook` for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionDenied, Notification, Stop, StopFailure and SessionEnd. It has no `PermissionRequest` hook: notch approvals work only with the sealed copies from `scripts/install-hooks.sh`. The plugin runs the scripts from the checkout, so prefer the sealed install for daily use.

### Source label, branch and jump

The hook script sends the app that launched Claude Code (`CLAUDE_CODE_ENTRYPOINT`, `__CFBundleIdentifier`, `TERM_PROGRAM`) and, on SessionStart, UserPromptSubmit and Stop, the current git branch and the GitHub repository (`owner/repo`, parsed from `git remote get-url origin`; only `github.com` https, ssh and `git@github.com:` remotes count, credentials in the URL are never forwarded, anything else sends nothing). Nothing else is read from your project.

### Usage, context and cost

Where the numbers come from depends on how you run Claude Code:

| | Desktop app and VS Code | Terminal |
|---|---|---|
| Context %, tokens, cost estimate | transcript, via the event hook | transcript, via the event hook |
| Context %, cost (exact) | not available | status line |
| 5h / 7d rate limits | not available | status line |

**Transcript (works everywhere).** The desktop app never runs the `statusLine` command, but every hook payload names the session transcript. On `Stop` (and `SubagentStop`, if you configure that hook; the setup snippet does not), `nubrix-hook` reads only the tail of that file (at most the last 6 MB and 400 relevant lines, never the whole file; it needs the system `jq`) and sends Nubrix a handful of numbers: the context size (`input + cache_creation + cache_read` tokens of the last assistant message), the token totals of the turn since your last prompt, the model id and the id of the last message (to avoid counting a turn twice). No message text is read into the request or sent. The transcript must be a regular `.jsonl` file you own, not a symlink, under `~/.claude/`; anything else is ignored. A turn longer than about 4000 transcript lines is not counted (the context figure still is). The extra work is roughly 40 to 70 ms per `Stop` on a 20 MB transcript, in the background.

Nubrix shows, per session, a context bar with the percentage and the session's tokens (input, output and cache writes; cache reads are not counted), and in the header `Today · 1.2M tokens · ~$4.20`, reset at local midnight. Each counted turn is also kept in a small usage ledger, `Application Support/Nubrix/claude-usage.json` (mode 0600, written atomically at most every 5 s, pruned to 7 days and 20,000 records). A record holds only the time, a short hash of the session id, the token count, the estimated cost and the model id; no prompts, paths, project names or content. The Today line is computed from that ledger. The context window is taken from the status line when known; otherwise it is 1M when the model id contains `[1m]` or when the context already exceeds 200k, and 200k otherwise. Costs are marked `~` because they are estimates from built-in list prices per million tokens (Opus 5.5 $4/$20, Opus 4.x and 5 $5/$25, Sonnet 5.x $2/$10, Sonnet 4.x $3/$15, Haiku 5.5 $0.10/$0.50, Haiku 4.5 $1/$5, cache writes 1.25x input, cache reads as listed or 0.1x input); plans, discounts and unknown models are not reflected. A status line cost, when present, replaces the estimate.

**Status line (terminal only).** Claude Code passes exact context usage, cost and rate limits only to the status line command. `nubrix-statusline` forwards that JSON to Nubrix in the background (it never delays the status line) and prints a compact line: `project · branch · model · ctx 42% · $1.23`. It works without `jq`; if `jq` is installed it is used for parsing. `scripts/install-hooks.sh` installs it with the other scripts and prints the setting; nothing edits your settings for you. Add it to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.config/nubrix/bin/nubrix-statusline"
  }
}
```

While a session sends status line updates, its percentage comes from there; otherwise from the transcript. The context bar is green below 60%, orange up to 85% and red above. When a session crosses 85% Nubrix shows a banner and an inbox entry ("Context 87% - consider /compact"). The status line's 5-hour and 7-day limits are a secondary source for the plan meters described below (claude.ai Pro, Max and Ultra subscribers, after the first response). If you already use a status line, call `nubrix-statusline` from it, or pipe its input to both.

**Official plan usage (`claude /usage`).** The primary source for the session (5-hour) and weekly meters is the number Claude itself reports: the helper (`NubrixHelper`, the unsandboxed XPC service) runs the installed Claude Code CLI as `claude /usage` (exact arguments below). This is a local command, not a model call (`total_cost_usd` 0, no turns), so it costs no tokens and does not count against your limits. It relies on the experimental `usage_report` that Claude Code attaches to that reply, so a future Claude Code version may change or drop it; the card then falls back to the other sources.
- Which binary: only fixed locations are tried, in order: `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `~/.local/bin/claude`, `~/.claude/local/claude` (real home from the system user database). No `PATH` lookup, nothing user supplied. Symlinks are resolved; the entry and its target must be regular files owned by you or root, executable and not group- or world-writable, and the target's folder must be owned by you or root and not world-writable. Otherwise Claude is treated as not installed.
- How it runs: fixed arguments (`claude -p --output-format stream-json --verbose --setting-sources project --tools "" --strict-mcp-config --no-session-persistence /usage`), stdin `/dev/null`, working directory a fresh empty temporary folder (removed afterwards), a minimal environment (`HOME`, `USER`, `LOGNAME`, `PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin`, `LANG`), a 30 s timeout (terminate, then kill) and at most 1 MB of output read. It uses the Claude Code login in `~/.claude`; `CLAUDE_CONFIG_DIR` and proxy variables are ignored. No tools and no MCP servers are loaded. `--setting-sources project` with an empty folder means no user or project settings are loaded, so your own Claude Code hooks (including `nubrix-hook`) do not fire and no phantom session appears in Nubrix; verified against a control run without the flag, where the user `SessionStart` hook does start.
- Self-check: the probe stops itself and the card shows "Update Claude Code to see plan usage" if the CLI does not list `/usage` as a command or reports any cost or turn. While `/usage` stays a local command it is free.
- What leaves the helper: only a small list of `{kind, group, percent, resetsAt, isActive, severity, scopeModel}` plus the fetch time, or one of `notInstalled`, `notSubscriber` (API-key login or no limits reported), `timeout`, `failed`. Raw output is never returned or logged. The app keeps the last good result (numbers and times only) in its preferences so the card shows something after a relaunch; it is marked as stale in the tooltip after 30 minutes.
- When it runs: about every 5 minutes while a Claude Code session was active in the last hour, otherwise every 30 minutes. The interval doubles on battery, and the timer does not poll in Low Power Mode. After 6 hours without Claude activity timer polling stops; the numbers still refresh when the notch opens on Home or the Claude tab (if the data is older than 2 minutes) and once after a `Stop` hook event (at most every 2 minutes). Paused while the Mac sleeps or is locked. Errors back off exponentially (5, 10, 20, then 30 minutes). Views are only updated when the numbers change.
- Alerts: when the session or weekly value first crosses 80% and again 95% in a window, Nubrix shows a closed-notch banner and an inbox entry ("Claude Code" source), once per window (keyed by its reset time).
- Settings, Notifications, Claude Code: "Show official plan usage (runs `claude /usage` in the background)" (`claudePlanUsageEnabled`, on by default). Off means nothing is run and the card uses the status line limits or the transcript estimate.

**Home tab card.** Next to the music player the Home tab shows a Claude card with your 5-hour and weekly usage. The card shows the official plan values when available: a `Oturum` / `Session` row (the 5-hour window, as Claude calls it) and a `Hafta` / `Week` row with percentage, bar and reset (`45%`, `sıfırlanma 17:10` / `resets 5:10 PM`), plus, when there is room, the busiest per-model weekly limit above 0% (`Opus 12%`; all of them are in the tooltip). When the status line also reports the limits (the 5-hour value within the last 6 hours, the 7-day value within the last 7 days, and its reset time still in the future), whichever source is fresher is used per row. A window whose reset time has passed is dropped. When neither official source is available it shows an estimate from the ledger over rolling windows of the last 5 hours and last 7 days: tokens and `~$` cost. Estimates are never shown as a percentage because the plan limit is unknown: the 5-hour bar compares the current 5 hours with your busiest 5 hours of the last 7 days, and the weekly row shows one small bar per day. Hover the card for the source and turn counts; click it to open the Claude tab. The card appears when there was any Claude activity in the last 7 days, is replaced by the meeting card while a meeting countdown is showing, refreshes once a minute only while the notch is open, and can be turned off in Settings, Notifications, "Show 5-hour and weekly usage on the Home tab" (`homeShowClaudeUsage`).

The ⓘ button in the Claude tab shows "All connected" when hook events arrived in the last 10 minutes and all four scripts are installed; otherwise it lists only what is wrong, with a one-line fix.

### Approving permissions from the notch

`nubrix-permission` is a synchronous `PermissionRequest` hook (the async `nubrix-hook` stays for state). It is installed by `scripts/install-hooks.sh` and is not part of the plugin. It sends the request to Nubrix and waits for your answer; Nubrix shows the tool and the full command, file or URL with Allow and Deny, and the script turns the answer into the documented `hookSpecificOutput` decision. Rules:

- The script only trusts a real Nubrix. It checks that the endpoint's process id is a running `Nubrix.app` of your user and, with `lsof`, that this process is the listener on the port. It then sends a random nonce; Nubrix answers with `HMAC-SHA256(token, nonce|decision|session_id)` (key: the token from the endpoint file) and the script checks it with the system `openssl` before printing allow or deny. Any mismatch, a stale endpoint file or a process that merely listens on the port produces no output, so Claude Code asks in its own dialog. The token is passed to `curl` through a file descriptor, never on the command line.
- The card shows the whole command in a scrollable monospaced box; Write, Edit and MultiEdit also show a scrollable preview of the content or a `-`/`+` diff. The tool's own `description` is labelled "Claude's description".
- Allow only becomes clickable after the card has been on screen for 0.7 s and the pointer has moved over it. It needs a real hardware mouse click: synthetic clicks and accessibility presses are ignored. Deny is always available.
- Risky prompts need a second click ("Allow anyway"). Risk flags: multi-line, long (over 500 characters) or truncated commands; invisible or direction-control characters; `rm -rf`, `sudo`, `git push --force`, `git reset --hard`, `curl | sh`; writes outside the project or to sensitive files (shell profiles, `.envrc`, `.vscode/tasks.json`, CI workflows, `.claude/`, Nubrix's own config folders, ...); reads of sensitive files; a sandbox bypass; a command that runs in the background; extra tool input that the card does not show; `replace_all` edits. Risky input is shown in red.
- Pending prompts are withdrawn when the screen locks, the Mac or its displays sleep, or the user session switches, and the card is never shown on the lock screen. If no notch can show the card (fullscreen app with "hide in fullscreen", approvals off), Nubrix answers immediately and Claude Code asks natively.
- Nothing is ever approved automatically. If Nubrix is not running, the toggle is off, no answer arrives in time, or anything is malformed, the script prints nothing and Claude Code asks in its own dialog as before.
- "Open in <app>" brings the source app forward and withdraws the notch prompt so you answer natively. Answering in Claude Code first also withdraws the prompt.
- Up to 5 requests queue ("1 of 3"); requests over 64 KB or beyond the queue are left to Claude Code.
- Wait time: 110 s in the desktop app and VS Code (Claude Code shows its own dialog at the same time and whichever answers first wins), 12 s in a terminal (the hook may hold the terminal dialog back while it waits). A 1 s liveness probe runs first, so a hung Nubrix costs about one second. `NUBRIX_PERMISSION_WAIT` (seconds) only applies with `NUBRIX_DEV=1`.
- Turn it off in Settings, Notifications, "Claude Code approvals".

Manual setup: in `~/.claude/settings.json`, add a second hook next to the existing async one under `PermissionRequest`, using the sealed copies:

```json
"PermissionRequest": [
  { "hooks": [
    { "type": "command", "command": "~/.config/nubrix/bin/nubrix-hook", "async": true, "timeout": 5 },
    { "type": "command", "command": "~/.config/nubrix/bin/nubrix-permission", "timeout": 125 }
  ] }
]
```

## GitHub integration

Nubrix reads GitHub with a **fine-grained, read-only personal access token** that you create for selected repositories (Settings, GitHub, "Create token on GitHub"). It is stored in the macOS Keychain (generic password, service `dev.nubrix.github`, account `token`, accessible after first unlock, this device only) and is never written to preferences, logs or files. With ad hoc signing the Keychain may ask once for access after you update Nubrix.

Why this and not something else:
- **Not the `gh` CLI login.** Its token carries broad write scopes (repo, workflow, ...); anything that can read the Keychain item or a hook could push code. A fine-grained token can only read the repositories you tick.
- **Not SSH keys.** They authenticate git over ssh, give full read and write access to every repository of the account, and cannot call the API that lists PRs, reviews and Actions runs.
- The sandboxed app cannot use another tool's credentials anyway; a token that only Nubrix holds can be revoked on github.com without affecting anything else.

Token permissions (all Read, everything else No access): Metadata (automatic), Pull requests, Actions, Commit statuses, and optionally Checks. Repository access: only select repositories.

How it talks to GitHub: `POST /graphql` (one query for your open PRs and your review requests with `statusCheckRollup`, `reviewDecision`, `mergeable`, `isDraft`), `GET /user`, `GET /user/repos` (the repositories the token can read, refreshed every 10 minutes), `GET /repos/{owner}/{repo}/actions/runs?per_page=10` with `If-None-Match` (a 304 costs no rate limit) for at most 10 watched repositories, and, only if GraphQL cannot read the check rollup, `GET /repos/{owner}/{repo}/commits/{sha}/status` and `.../check-runs`. Requests carry `X-GitHub-Api-Version: 2022-11-28`, redirects are never followed and the token only goes to `api.github.com`. `X-RateLimit-Remaining` and `Retry-After` are honoured: below a 25 request reserve, or after a 403/429, Nubrix stops until the reset time.

Polling: every 2 minutes; every 30 seconds while the GitHub section is visible (or a run is in progress, on AC power and outside Low Power Mode); every 7.5 minutes when nothing is running and none of your Claude sessions has a GitHub repository. It backs off when offline or when requests fail (up to 15 minutes), is paused while the Mac sleeps or is locked and without a token, and refreshes on opening the section. Watched repositories: the ones the token can read (switch them off in Settings), repositories you add by hand, the repositories of your Claude sessions and of your open PRs.

## notchctl

`scripts/install-hooks.sh` installs a sealed copy at `~/.config/nubrix/bin/notchctl`. Use it from there instead of symlinking the git checkout:

```sh
~/.config/nubrix/bin/notchctl notify "Build done" --title api --style success
~/.config/nubrix/bin/notchctl ping
```

See [cli/README.md](cli/README.md) for styles, duration, putting it on your `PATH` and more examples.

## Privacy and security

- Everything stays on your Mac. Nubrix has no analytics, no account and sends nothing to a Nubrix server. It is sandboxed and has no auto-updater.
- Network use, complete list:
  - `api.github.com`, only if you add a fine-grained read-only token (off until then; see [GitHub integration](#github-integration)). The token goes nowhere else.
  - `lrclib.net` receives the track title and artist when lyrics are turned on (off by default).
  - LottieFiles: a visualizer animation (JSON) is downloaded when the built-in music visualizer is turned off in Settings.
  - Artwork URLs supplied by Spotify or YouTube Music are fetched to show the cover.
  - `localhost:26538`, the local API of the YouTube Music desktop app, when that controller is used.
  - The `claude` command-line tool, run by the helper to read your plan usage (see [Usage, context and cost](#usage-context-and-cost)). Turn it off in Settings, Notifications, Claude Code.
- The event server binds to the loopback interface only (127.0.0.1) on a random port and requires a random bearer token. Port, token and process id are written to `~/.config/nubrix-run/agent-endpoint` (file 0600 in a 0700 directory). The app can read `~/.config/nubrix/` (the sealed hook scripts) but cannot write there, so it cannot change what Claude Code runs.
- Vitrin history is a SQLite database with image files beside it, stored in the app container (`~/Library/Containers/dev.nubrix.app/Data/Library/Application Support/Nubrix/Vitrin`) with 0600/0700 permissions. It is not encrypted yet. The Vitrin panel is hidden from screen sharing and recording by default (Settings, Vitrin).
- The secret guard is a heuristic. It reduces the chance of storing a credential but cannot catch everything; use excluded apps and the capture toggles, and clear the history from Settings, Vitrin when needed.

See [SECURITY.md](SECURITY.md) for reporting problems.

## Roadmap

See [docs/nubrix/ROADMAP.md](docs/nubrix/ROADMAP.md).

## Credits

- [boring.notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam, the project Nubrix is forked from (GPL-3.0)
- Ideas and selected logic for Vitrin from ClipBoardLine (MIT) and Tendedero (MIT)
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause)
- Every other bundled or linked dependency, with its copyright line and license, is listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES)

## License

GNU General Public License v3.0, see [LICENSE](LICENSE). [NOTICE](NOTICE) states that Nubrix is a modified version of boring.notch, which commit it was forked from and who modified it. `LICENSE`, `NOTICE` and `THIRD_PARTY_LICENSES` are also bundled in the app's Resources.
