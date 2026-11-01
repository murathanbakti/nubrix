# Nubrix

Nubrix is a notch bar for macOS built for developers. It has music controls, volume and brightness HUDs and a file shelf, and adds three things on top: live status of your Claude Code sessions (with approvals you can answer from the notch), a clipboard and screenshot showcase called Vitrin, and a small toolbox for scripts, local dev servers and GitHub.

Everything runs locally. There is no account, no cloud service, no telemetry and no auto-updater. The few optional network uses are listed under [Privacy and security](#privacy-and-security).

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)](#requirements)
[![Latest release](https://img.shields.io/github/v/release/murathanbakti/nubrix)](https://github.com/murathanbakti/nubrix/releases/latest)

<!-- screenshot: docs/images/hero.png (TODO, see docs/images/README.md) -->

Contents: [Features](#features) · [Install](#install) · [First launch](#first-launch-and-gatekeeper) · [Permissions](#permissions) · [Claude Code setup](#claude-code-setup) · [notchctl](#notchctl) · [Settings](#settings) · [Privacy and security](#privacy-and-security) · [Troubleshooting](#troubleshooting) · [Updating](#updating) · [Uninstall](#uninstall) · [Contributing](#building-and-contributing) · [License and credits](#license)

## Features

**Claude Code sessions** (notch tab "Claude")
- Shows each Claude Code session as Working, Needs you, Failed, Done or Idle, fed by Claude Code hooks
- Works with the Claude Code CLI, the desktop app and the VS Code extension; each row shows where the session runs (Desktop, Terminal · iTerm, VS Code, Cursor, ...) and its git branch, and clicking a row brings that app to the front
- Context window bar and session cost per row, and your 5-hour and weekly plan usage as percentages ([details](#usage-context-and-cost))
- Approve or deny Claude Code permission requests from the notch (Allow needs a real mouse click and risky requests need a second click; see [Approving permissions from the notch](#approving-permissions-from-the-notch))
- A done, failed or needs-you event shows a banner on the closed notch and an inbox entry

<!-- screenshot: docs/images/claude-sessions.png, docs/images/permission-approval.png, docs/images/usage.png -->

**Vitrin, a clipboard and screenshot showcase** (notch tab "Vitrin", global shortcut Control-Option-V)
- Keeps copied images, text and links locally and shows them as cards, with a filter for All, Images, Screenshots, Text and Links
- Screenshots: after you allow read-only access to the folder where macOS saves screenshots, new screenshots appear in Vitrin and a thumbnail banner shows in the closed notch. Nubrix only reads new files there and never changes them. Screenshots you drag out of the macOS floating preview are not saved to disk, so Vitrin cannot show them (see [Troubleshooting](#troubleshooting))
- Showcase panel under the notch with search, keyboard navigation (arrows, Enter to copy, P to pin, Delete to remove, Space for a large preview, Esc to close)
- Secret guard: text that looks like a credential (private keys, `sk-` keys, GitHub tokens, AWS keys, Slack tokens, JWTs, `Bearer` tokens, long high-entropy strings) is never stored; concealed, transient and password-manager pasteboard types are skipped
- Excluded apps: nothing copied while an excluded app is frontmost is stored (password managers and Keychain Access are excluded by default; the list is editable)
- Retention: history expires after a configurable period (default 30 days); pinned items never expire
- Per-type capture toggles for images, text, links and screenshots

<!-- screenshot: docs/images/vitrin.png -->

**Developer insights** (inside Vitrin)
- Detects JSON, code language (Swift, TypeScript/JavaScript, Python, Go, Rust, SQL, Shell, YAML, HTML, CSS), Base64, percent-encoded text, Unix timestamps, colors and UUIDs
- Cards show a badge and a lightweight syntax-highlighted preview
- Actions: copy pretty or minified JSON, copy decoded Base64 or URL text, copy ISO date, copy hex or rgb

**Dev tab, GitHub and notchctl**
- `notchctl` is a bash and curl CLI that shows a banner in the closed notch, for example `gh run watch && notchctl notify "CI green"`
- The "Dev" tab keeps the last notifications and shows which localhost ports (3000, 5173, 8080, 5432 and others, configurable) are listening; clicking an HTTP port opens it in the browser
- The Dev tab has a GitHub, Servers and Notifications switch. GitHub shows three columns: PRs where your review is requested, your open PRs (CI checks, review decision, merge conflicts, draft) and recent GitHub Actions runs of your watched repositories
- A closed-notch banner and a notification entry appear for a new review request, your PR's CI turning red or green, a merge conflict, and a failed workflow run on a default branch, on your PR branches, on your Claude session branches or started by you
- Each Claude session row shows the PR of its branch as a small chip (`#123` with a CI mark); click it to open the PR
- Read-only: Nubrix never writes to GitHub. See [GitHub integration](#github-integration)

<!-- screenshot: docs/images/dev-tab.png -->

**Music, HUDs and shelf**
- Live music activity with playback controls and a visualizer. Sources: system Now Playing, Apple Music, Spotify and YouTube Music. Optional synced lyrics (off by default)
- Custom volume, display brightness and keyboard brightness HUDs in the notch (optional; needs Accessibility, see [Permissions](#permissions))
- File shelf with drag and drop and quick share

<!-- screenshot: docs/images/music.png -->

**Calendar, meetings and mirror**
- Calendar sheet that drops from the notch (header date pill or Control-Option-K) for events and reminders, with a day panel and quick add
- Meeting countdown in the closed notch with a Join button when the event has a Zoom, Google Meet, Teams, Webex, Whereby or Slack Huddle link
- Mirror: a camera preview that splits out of the notch (Control-Option-M)

<!-- screenshot: docs/images/calendar.png -->

## Requirements

- macOS 14 Sonoma or later, Apple silicon or Intel
- Building from source needs Xcode 26 or later

Nubrix works on Macs with and without a notch. Without a notch it draws the bar at the top centre of the display; the height is set in Settings, General ("Notch height on non-notch displays"). "Show on all displays" is off by default.

## Install

Releases are published on [GitHub Releases](https://github.com/murathanbakti/nubrix/releases) for each tag `vX.Y.Z`. The asset is `Nubrix-<version>.zip` (it contains `Nubrix.app`, a universal arm64 and x86_64 build) with a `Nubrix-<version>.zip.sha256` checksum, both built by GitHub Actions. The current version is 0.1.0.

The app is ad-hoc signed with the hardened runtime and is **not notarized**: there is no paid Apple Developer account. macOS will therefore block the first launch; see [First launch and Gatekeeper](#first-launch-and-gatekeeper).

### Homebrew (recommended)

```sh
brew tap murathanbakti/tap
brew trust --tap murathanbakti/tap
brew install --cask nubrix
```

Homebrew 7 only installs from non-official taps you have explicitly trusted, which is what `brew trust` does. Homebrew no longer supports `--no-quarantine`, so the app is quarantined and the first launch is blocked by Gatekeeper.

### Install script

```sh
curl -fsSL https://raw.githubusercontent.com/murathanbakti/nubrix/main/scripts/install.sh | bash
```

The script downloads the latest release zip and its `.sha256`, verifies the checksum, checks the bundle identifier and the code signature, and installs `Nubrix.app` to `/Applications`. Environment variables: `NUBRIX_VERSION` (install a specific version), `NUBRIX_INSTALL_DIR` (default `/Applications`) and `NUBRIX_SHA256` (an expected checksum that you copied from the release page; the script then checks the download against it as well).

Be aware of what this does and does not give you. Files downloaded with `curl` carry no quarantine flag, so macOS shows no Gatekeeper prompt. Trust rests on HTTPS to GitHub, the checksum and the signature check, not on Apple's notarization. Piping a script into a shell runs whatever the server sends, so read it first if you can:

```sh
curl -fsSLO https://raw.githubusercontent.com/murathanbakti/nubrix/main/scripts/install.sh
less install.sh
bash install.sh
```

### From source

```sh
git clone https://github.com/murathanbakti/nubrix.git
cd nubrix
scripts/install-local.sh
```

This needs Xcode 26 or later. `scripts/install-local.sh [--open]` builds Release into `~/Library/Caches/Nubrix/DerivedData`, verifies the bundle (hardened runtime on, no `get-task-allow`, only `NubrixHelper.xpc` and only the Lottie and MediaRemoteAdapter frameworks), quits a running Nubrix, installs `Nubrix.app` to `/Applications` and then runs `scripts/install-hooks.sh`. With `--open` it starts the app afterwards. It stops if a check fails. A build you made yourself is signed ad hoc on your Mac and opens directly, with no Gatekeeper prompt.

## First launch and Gatekeeper

For Homebrew installs, and for anything you downloaded with a browser, the first launch goes like this:

1. Open Nubrix (Spotlight or `/Applications`). macOS says it cannot verify that Nubrix is free of malware. Dismiss the dialog (Done).
2. Open System Settings, Privacy & Security, and scroll down to the message "Nubrix was blocked to protect your Mac".
3. Click "Open Anyway" and confirm with your admin password or Touch ID. Open Nubrix again and confirm.

<!-- screenshot: docs/images/gatekeeper-open-anyway.png -->

You do this once per install and once after each upgrade. On macOS 15 Sequoia and later, the older right-click then Open shortcut no longer bypasses this check; use Privacy & Security. You do not need to, and should not, turn Gatekeeper off (`spctl --master-disable`): it protects every other app on your Mac.

If you built or verified the app yourself and prefer the terminal, `xattr -d com.apple.quarantine /Applications/Nubrix.app` removes the quarantine flag for that one app. Only do this for a copy whose origin and checksum you have verified.

## Permissions

Nubrix asks for access only when you use the feature that needs it (the onboarding screen also offers the ones marked with an asterisk):

| Permission | Why | When |
|---|---|---|
| Calendars and Reminders (full access)* | Show upcoming events and reminders, meeting countdown, add events from the calendar sheet | Calendar and meeting features |
| Camera* | Mirror preview | When you open Mirror |
| Accessibility* | Intercept volume and brightness keys to replace the system HUDs. Granted to the helper process `NubrixHelper`, which is not sandboxed | Only if you turn on "Replace system HUD" |
| Automation (Apple Events) | Control Spotify and Apple Music, the only two apps Nubrix is allowed to script | When you pick those sources in Settings, Media |
| Screenshot folder | A folder picker; Nubrix keeps read-only access to the folder you choose | When you enable screenshots in Vitrin |
| Pasteboard access | On recent macOS versions macOS may ask whether Nubrix may read what other apps copy. Vitrin cannot capture anything while access is denied | When Vitrin starts capturing |
| Keychain | Stores the optional GitHub token | When you save a token |

Nubrix does not use the macOS notification centre. Its banners are drawn in the notch. There is no Full Disk Access and no Screen Recording permission.

## Claude Code setup

Nubrix listens on a loopback HTTP server; hook scripts forward Claude Code hook events to it. Hooks are asynchronous, have a short timeout and always exit 0, so they never block or slow down Claude Code. If Nubrix is not running, the scripts do nothing.

The hook kit is bundled in the app at `/Applications/Nubrix.app/Contents/Resources/nubrix-hooks/`.

**1. Install the sealed scripts**

- Homebrew or install script:
  ```sh
  /Applications/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh
  ```
  (adjust the path if you used `NUBRIX_INSTALL_DIR`). When run from the app bundle it first verifies the app's code signature.
- From source: `scripts/install-hooks.sh` (already run by `scripts/install-local.sh`).

The installer copies `nubrix-hook`, `nubrix-permission`, `nubrix-statusline` and `notchctl` to `~/.config/nubrix/bin/` (directories mode 0700, files 0500) and can be run again at any time. It then prints a `~/.claude/settings.json` snippet: hooks for all events, the `statusLine` command and `permissions.deny` rules. **It never edits `~/.claude/settings.json`**: you paste or merge the snippet yourself. Re-run the installer after every Nubrix update to refresh the copies. It warns if your settings still point into a source checkout.

**2. Merge the snippet into `~/.claude/settings.json`**

The snippet looks like this (the installer prints the exact absolute paths for your machine; repeat the hook block for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, PermissionDenied, Notification, Stop, StopFailure and SessionEnd):

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
  "statusLine": { "type": "command", "command": "~/.config/nubrix/bin/nubrix-statusline" },
  "permissions": {
    "deny": [
      "Edit(~/.config/nubrix/**)", "Write(~/.config/nubrix/**)",
      "Edit(~/.config/nubrix-run/**)", "Write(~/.config/nubrix-run/**)",
      "Read(~/.config/nubrix-run/**)"
    ]
  }
}
```

The `PermissionRequest` entry that enables notch approvals is shown under [Approving permissions from the notch](#approving-permissions-from-the-notch). `permissions.deny` is merged with your existing list. If you already use a status line, call `nubrix-statusline` from it, or pipe its input to both. Drop the `nubrix-permission` entry to keep Claude Code's own permission dialogs only.

The `notchctl` command can be put on your `PATH` with `ln -sf ~/.config/nubrix/bin/notchctl ~/.local/bin/notchctl`.

**3. Check the connection.** Start a Claude Code session. The info button in the Claude tab shows "All connected" when hook events arrived in the last 10 minutes and all four scripts are installed; otherwise it lists only what is wrong, with a one-line fix.

### Why sealed copies

Hooks run with your full privileges in every Claude Code session, so they must not live in a folder that Claude, a `git checkout` or a pull request can rewrite. That is why the installer makes read-only copies outside any repository:

- **Two folders, two jobs.** `~/.config/nubrix/` holds the sealed scripts; the sandboxed app can only read it. `~/.config/nubrix-run/` holds `agent-endpoint` (`port token pid`, file 0600 in a 0700 directory) and is the only place under `~/.config` the app can write. So even a compromised app cannot modify the scripts Claude Code runs.
- **Deny rules.** The snippet adds `permissions.deny` rules so Claude cannot edit the scripts or read the token: `Edit` and `Write` for `~/.config/nubrix/**` and `~/.config/nubrix-run/**`, and `Read(~/.config/nubrix-run/**)`.
- **What the scripts check.** They pin `PATH` to the system directories and call every tool by absolute path. Before sending the token they check that the process id in the endpoint file is a running `Nubrix.app` owned by you, and ignore the file otherwise. The permission hook additionally checks with `lsof` that this process is the one listening on the port, and verifies an HMAC reply proof (see [Approving permissions from the notch](#approving-permissions-from-the-notch)).
- `NUBRIX_ENDPOINT_FILE` and `NUBRIX_PERMISSION_WAIT` are only honoured when `NUBRIX_DEV=1` is set (tests); a project's `.claude/settings.json` cannot redirect the hooks.
- Large `tool_response` and file contents are stripped by `nubrix-hook` before forwarding (with the system `jq`; without it, events over 256 KB are reduced to session, tool and event name).

**Plugin (status only, source checkout).** For a quick look without touching your settings you can load the plugin from a clone of the repository:

```sh
claude --plugin-dir /path/to/nubrix/claude-plugin
```

It registers `nubrix-hook` for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionDenied, Notification, Stop, StopFailure and SessionEnd. It has no `PermissionRequest` hook: notch approvals work only with the sealed copies. The plugin runs the scripts from the checkout, so prefer the sealed install for daily use.

### Source label, branch and jump

The hook script sends the app that launched Claude Code (`CLAUDE_CODE_ENTRYPOINT`, `__CFBundleIdentifier`, `TERM_PROGRAM`) and, on SessionStart, UserPromptSubmit and Stop, the current git branch and the GitHub repository (`owner/repo`, parsed from `git remote get-url origin`; only `github.com` https, ssh and `git@github.com:` remotes count, credentials in the URL are never forwarded, anything else sends nothing). Nothing else is read from your project.

### Usage, context and cost

Where the numbers come from depends on how you run Claude Code:

| | Desktop app and VS Code | Terminal |
|---|---|---|
| Context %, tokens, cost estimate | transcript, via the event hook | transcript, via the event hook |
| Context %, cost (exact) | not available | status line |
| 5h / 7d rate limits | official plan usage (`claude /usage`) | official plan usage, or the status line |

**Transcript (works everywhere).** The desktop app never runs the `statusLine` command, but every hook payload names the session transcript. On `Stop` (and `SubagentStop`, if you configure that hook; the setup snippet does not), `nubrix-hook` reads only the tail of that file (at most the last 6 MB and 400 relevant lines, never the whole file; it needs the system `jq`) and sends Nubrix a handful of numbers: the context size (`input + cache_creation + cache_read` tokens of the last assistant message), the token totals of the turn since your last prompt, the model id and the id of the last message (to avoid counting a turn twice). No message text is read into the request or sent. The transcript must be a regular `.jsonl` file you own, not a symlink, under `~/.claude/`; anything else is ignored. A turn longer than about 4000 transcript lines is not counted (the context figure still is). The extra work is roughly 40 to 70 ms per `Stop` on a 20 MB transcript, in the background.

Nubrix shows, per session, a context bar with the percentage and the session's tokens (input, output and cache writes; cache reads are not counted), and in the header `Today · 1.2M tokens · ~$4.20`, reset at local midnight. Each counted turn is also kept in a small usage ledger, `Application Support/Nubrix/claude-usage.json` (mode 0600, written atomically at most every 5 s, pruned to 7 days and 20,000 records). A record holds only the time, a short hash of the session id, the token count, the estimated cost and the model id; no prompts, paths, project names or content. The Today line is computed from that ledger. The context window is taken from the status line when known; otherwise it is 1M when the model id contains `[1m]` or when the context already exceeds 200k, and 200k otherwise. Costs are marked `~` because they are estimates from built-in list prices per million tokens (Opus 5.5 $4/$20, Opus 4.x and 5 $5/$25, Sonnet 5.x $2/$10, Sonnet 4.x $3/$15, Haiku 5.5 $0.10/$0.50, Haiku 4.5 $1/$5, cache writes 1.25x input, cache reads as listed or 0.1x input); plans, discounts and unknown models are not reflected. A status line cost, when present, replaces the estimate.

**Status line (terminal only).** Claude Code passes exact context usage, cost and rate limits only to the status line command. `nubrix-statusline` forwards that JSON to Nubrix in the background (it never delays the status line) and prints a compact line: `project · branch · model · ctx 42% · $1.23`. It works without `jq`; if `jq` is installed it is used for parsing. While a session sends status line updates, its percentage comes from there; otherwise from the transcript. The context bar is green below 60%, orange up to 85% and red above. When a session crosses 85% Nubrix shows a banner and an inbox entry ("Context 87% - consider /compact"). The status line's 5-hour and 7-day limits are a secondary source for the plan meters described below (claude.ai Pro, Max and Ultra subscribers, after the first response).

**Official plan usage (`claude /usage`).** The primary source for the session (5-hour) and weekly meters is the number Claude itself reports: the helper (`NubrixHelper`, the unsandboxed XPC service) runs the installed Claude Code CLI as `claude /usage`. This is a local command, not a model call (`total_cost_usd` 0, no turns), so it costs no tokens and does not count against your limits. It relies on the experimental `usage_report` that Claude Code attaches to that reply, so a future Claude Code version may change or drop it; the card then falls back to the other sources.
- **The Claude CLI must be signed in.** Run `claude auth login` once in a terminal. If `/usage` returns no report, the helper also runs `claude auth status`; when that says you are signed out, the card shows "Claude sign-in needed: claude auth login" instead of silently falling back to transcript tokens. API-key logins and accounts without plan limits show "Plan usage needs a Claude subscription".
- Which binary: only fixed locations are tried, in order: `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `~/.local/bin/claude`, `~/.claude/local/claude` (real home from the system user database). No `PATH` lookup, nothing user supplied. Symlinks are resolved; the entry and its target must be regular files owned by you or root, executable and not group- or world-writable, and the target's folder must be owned by you or root and not world-writable. Otherwise Claude is treated as not installed ("Claude Code not found").
- How it runs: fixed arguments (`claude -p --output-format stream-json --verbose --setting-sources project --tools "" --strict-mcp-config --no-session-persistence /usage`), stdin `/dev/null`, working directory a fresh empty temporary folder (removed afterwards), a minimal environment (`HOME`, `USER`, `LOGNAME`, `PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin`, `LANG`), a 30 s timeout and at most 1 MB of output read. The command is started as a short-lived launchd job (`dev.nubrix.usage-probe.*`, removed afterwards) so that the Claude CLI can read its own login from the macOS Keychain; if launchd refuses the job, the helper falls back to spawning the process directly. It uses the Claude Code login in `~/.claude`; `CLAUDE_CONFIG_DIR` and proxy variables are ignored. No tools and no MCP servers are loaded. `--setting-sources project` with an empty folder means no user or project settings are loaded, so your own Claude Code hooks (including `nubrix-hook`) do not fire and no phantom session appears in Nubrix.
- Self-check: the probe stops itself and the card shows "Update Claude Code to see plan usage" if the CLI does not list `/usage` as a command or reports any cost or turn. While `/usage` stays a local command it is free.
- What leaves the helper: only a small list of `{kind, group, percent, resetsAt, isActive, severity, scopeModel}` plus the fetch time, or one of `notInstalled`, `notSubscriber` (API-key login or no limits reported), `signedOut`, `unsupported`, `timeout`, `failed`. Raw output is never returned or logged. The app keeps the last good result (numbers and times only) in its preferences so the card shows something after a relaunch; it is marked as stale in the tooltip after 30 minutes.
- When it runs: about every 5 minutes while a Claude Code session was active in the last hour, otherwise every 30 minutes. The interval doubles on battery, and the timer does not poll in Low Power Mode. After 6 hours without Claude activity timer polling stops; the numbers still refresh when the notch opens on Home or the Claude tab (if the data is older than 2 minutes) and once after a `Stop` hook event (at most every 2 minutes). Paused while the Mac sleeps or is locked. Errors back off exponentially (5, 10, 20, then 30 minutes). Views are only updated when the numbers change.
- Alerts: when the session or weekly value first crosses 80% and again 95% in a window, Nubrix shows a closed-notch banner and an inbox entry ("Claude Code" source), once per window (keyed by its reset time).
- Setting: Settings, Notifications, Claude Code: "Show official plan usage (runs `claude /usage` in the background)" (on by default). Off means nothing is run and the card uses the status line limits or the transcript estimate.

**Home tab card.** Next to the music player the Home tab shows a Claude card with your 5-hour and weekly usage. The card shows the official plan values when available: a `Session` row (the 5-hour window, as Claude calls it) and a `Week` row with percentage, bar and reset (`45%`, `resets 5:10 PM`), plus, when there is room, the busiest per-model weekly limit above 0% (`Opus 12%`; all of them are in the tooltip). When the status line also reports the limits (the 5-hour value within the last 6 hours, the 7-day value within the last 7 days, and its reset time still in the future), whichever source is fresher is used per row. A window whose reset time has passed is dropped. When neither official source is available it shows an estimate from the ledger over rolling windows of the last 5 hours and last 7 days: tokens and `~$` cost. Estimates are never shown as a percentage because the plan limit is unknown. Hover the card for the source and turn counts; click it to open the Claude tab. The card appears when there was any Claude activity in the last 7 days, is replaced by the meeting card while a meeting countdown is showing, refreshes once a minute only while the notch is open, and can be turned off in Settings, Notifications, "Show 5-hour and weekly usage on the Home tab". The labels are shown in Turkish when the system language is Turkish.

### Approving permissions from the notch

`nubrix-permission` is a synchronous `PermissionRequest` hook (the async `nubrix-hook` stays for state). It is installed by the installer and is not part of the plugin. It sends the request to Nubrix and waits for your answer; Nubrix shows the tool and the full command, file or URL with Allow and Deny, and the script turns the answer into the documented `hookSpecificOutput` decision. Rules:

- The script only trusts a real Nubrix. It checks that the endpoint's process id is a running `Nubrix.app` of your user and, with `lsof`, that this process is the listener on the port. It then sends a random nonce; Nubrix answers with `HMAC-SHA256(token, nonce|decision|session_id)` (key: the token from the endpoint file) and the script checks it with the system `openssl` before printing allow or deny. Any mismatch, a stale endpoint file or a process that merely listens on the port produces no output, so Claude Code asks in its own dialog. The token is passed to `curl` through a file descriptor, never on the command line.
- The card shows the whole command in a scrollable monospaced box; Write, Edit and MultiEdit also show a scrollable preview of the content or a `-`/`+` diff. The tool's own `description` is labelled "Claude's description".
- Allow only becomes clickable after the card has been on screen for 0.7 s and the pointer has moved over it. It needs a real hardware mouse click: synthetic clicks and accessibility presses are ignored. Deny is always available.
- Risky prompts need a second click ("Allow anyway"). Risk flags: multi-line, long (over 500 characters) or truncated commands; invisible or direction-control characters; `rm -rf`, `sudo`, `git push --force`, `git reset --hard`, `curl | sh`; writes outside the project or to sensitive files (shell profiles, `.envrc`, `.vscode/tasks.json`, CI workflows, `.claude/`, Nubrix's own config folders, ...); reads of sensitive files; a sandbox bypass; a command that runs in the background; extra tool input that the card does not show; `replace_all` edits. Risky input is shown in red.
- **Questions and plans are not shown in the notch.** Claude's own questions (`AskUserQuestion`) and plan approvals (`ExitPlanMode`) need Claude's own interface, so the hook ignores them and the app rejects such payloads. You answer them in the terminal or the Claude desktop app, as before.
- Pending prompts are withdrawn when the screen locks, the Mac or its displays sleep, or the user session switches, and the card is never shown on the lock screen. If no notch can show the card (for example a fullscreen app while Settings, Media, "Full screen behavior" hides the notch, or approvals turned off), Nubrix answers immediately and Claude Code asks natively.
- Nothing is ever approved automatically. If Nubrix is not running, the toggle is off, no answer arrives in time, or anything is malformed, the script prints nothing and Claude Code asks in its own dialog as before.
- "Open in <app>" brings the source app forward and withdraws the notch prompt so you answer natively. Answering in Claude Code first also withdraws the prompt.
- Up to 5 requests queue ("1 of 3"); requests over 64 KB or beyond the queue are left to Claude Code.
- Wait time: 110 s in the desktop app and VS Code (Claude Code shows its own dialog at the same time and whichever answers first wins), 12 s in a terminal (the hook may hold the terminal dialog back while it waits). A 1 s liveness probe runs first, so a hung Nubrix costs about one second. `NUBRIX_PERMISSION_WAIT` (seconds) only applies with `NUBRIX_DEV=1`.
- Turn it off in Settings, Notifications, "Approve Claude Code permissions from the notch".

The settings entry for approvals (printed by the installer) puts the synchronous hook next to the async one under `PermissionRequest`:

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

The installer puts a sealed copy at `~/.config/nubrix/bin/notchctl`. Use it from there instead of symlinking the git checkout:

```sh
~/.config/nubrix/bin/notchctl notify "Build done" --title api --style success
~/.config/nubrix/bin/notchctl ping
```

See [cli/README.md](cli/README.md) for styles, duration, putting it on your `PATH` and more examples.

## Settings

Open Settings from the menu bar icon or, if enabled, the settings icon in the open notch.

| Tab | What it controls |
|---|---|
| General | Menu bar icon, launch at login, displays, notch size and non-notch height, open on hover, gestures, haptics |
| Appearance | Accent colour, settings icon in the notch, spectrogram and album-art options, custom Lottie visualizers, mirror options |
| Media | Music source (Now Playing, Apple Music, Spotify, YouTube Music), lyrics, full screen behavior |
| Calendar | Calendars and reminders shown in the notch and the calendar sheet |
| HUDs | Replace the system volume, display and keyboard-brightness HUDs (needs Accessibility) |
| Battery | Power and charging notifications in the notch |
| Shelf | File shelf behaviour |
| Vitrin | Capture toggles, screenshot folder and preview, retention, excluded apps, hide from screen sharing, clear history |
| Dev | Which localhost ports are watched |
| GitHub | Token, watched repositories, notification toggles |
| Notifications | Inbox sources (Claude Code, notchctl, GitHub), notch approvals, plan usage, Home usage card, meeting countdown |
| Shortcuts | Global keyboard shortcuts (defaults: Control-Option-V Vitrin, Control-Option-K calendar, Control-Option-M mirror) |
| Advanced | Additional options |
| About | Version, credits and licenses |

## Privacy and security

- Everything stays on your Mac. Nubrix has no analytics, no account and sends nothing to a Nubrix server. It has no auto-updater.
- Network use, complete list:
  - `api.github.com`, only if you add a fine-grained read-only token (off until then; see [GitHub integration](#github-integration)). The token goes nowhere else.
  - `lrclib.net` receives the track title and artist when lyrics are turned on (off by default).
  - LottieFiles: a visualizer animation (JSON) is downloaded when the built-in music visualizer is turned off in Settings.
  - Artwork URLs supplied by Spotify or YouTube Music are fetched to show the cover.
  - `localhost:26538`, the local API of the YouTube Music desktop app, when that controller is used.
  - The `claude` command-line tool, run by the helper to read your plan usage (see [Usage, context and cost](#usage-context-and-cost)); Claude itself talks to Anthropic as it always does. Turn it off in Settings, Notifications, Claude Code.
- **Sandbox and helper split.** The app is sandboxed. The only unsandboxed part is the small XPC service `NubrixHelper`, used for Accessibility-based key handling, brightness and the `claude /usage` probe. The app can read `~/.config/nubrix/` (the sealed hook scripts) but cannot write there, so it cannot change what Claude Code runs; its only writable config location is `~/.config/nubrix-run/`.
- **Local endpoint.** The event server binds to the loopback interface only (127.0.0.1) on a random port, authenticates on request headers with a random bearer token and caps connections. Port, token and process id are written to `~/.config/nubrix-run/agent-endpoint` (file 0600 in a 0700 directory). Hook scripts verify the server with an HMAC challenge before trusting an answer.
- **Sealed hooks and deny rules.** See [Why sealed copies](#why-sealed-copies). Nothing edits `~/.claude/settings.json`.
- **Vitrin.** History is a SQLite database with image files beside it, stored in the app container (`~/Library/Containers/dev.nubrix.app/Data/Library/Application Support/Nubrix/Vitrin`) with 0600/0700 permissions. It is not encrypted yet. The Vitrin panel is hidden from screen sharing and recording by default (Settings, Vitrin). The secret guard is a heuristic: it reduces the chance of storing a credential but cannot catch everything; use excluded apps and the capture toggles, and clear the history from Settings, Vitrin when needed.
- **GitHub token.** Kept in the macOS Keychain only, read-only and limited to the repositories you chose.
- **Signing.** Release builds are ad-hoc signed with the hardened runtime (no `get-task-allow`) and are not notarized. The app carries `disable-library-validation` because the bundled MediaRemote adapter is ad-hoc signed too. See [docs/nubrix/SUPPLY-CHAIN.md](docs/nubrix/SUPPLY-CHAIN.md) and [docs/nubrix/AUDIT-2026-10-31-release.md](docs/nubrix/AUDIT-2026-10-31-release.md) for the audit and known limits.

See [SECURITY.md](SECURITY.md) for reporting problems.

## Troubleshooting

**macOS says Nubrix cannot be opened or is "damaged" or from an unidentified developer.** See [First launch and Gatekeeper](#first-launch-and-gatekeeper): Privacy & Security, "Open Anyway". Repeat after each upgrade.

**The Keychain asks for access, or Camera, Calendar or Accessibility permissions are asked again after an update.** Release builds are ad-hoc signed, so the code identity changes with every version, and macOS ties Keychain access and permission grants to it. Click "Always Allow" for the Keychain item, and grant the permissions again if macOS asks. Your GitHub token is not lost.

**The Home card or Claude tab says "Claude sign-in needed: claude auth login".** The Claude Code CLI is signed out. Run `claude auth login` in a terminal. The card updates on the next refresh (open the notch on Home or the Claude tab). "Plan usage needs a Claude subscription" means an API-key login or an account without plan limits; "Claude Code not found" means `claude` is not in one of the fixed locations listed under [Usage, context and cost](#usage-context-and-cost); "Update Claude Code to see plan usage" means your CLI version has no free local `/usage` command.

**No Claude sessions show up, or the info button lists problems.** Re-run the hook installer (`/Applications/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh`, or `scripts/install-hooks.sh` from a source checkout) and compare `~/.claude/settings.json` with the snippet it prints: the commands must point at `~/.config/nubrix/bin/...` and exist. Nubrix must be running. Claude Code reads hooks at session start, so start a new session after changing settings.

**Approvals do not appear in the notch.** They need the `nubrix-permission` entry under `PermissionRequest` in your settings (not part of the plugin), the toggle in Settings, Notifications, and a running Nubrix. Claude's own questions and plan approvals are intentionally not shown there; answer those in Claude. If no notch can show the card (for example the notch is hidden for a fullscreen app, see Settings, Media, "Full screen behavior"), Claude Code asks in its own dialog.

**A screenshot I dragged out of the macOS floating preview is not in Vitrin.** macOS writes a screenshot file only after the floating preview closes on its own. If you drag the preview somewhere or swipe it away, no file is written, so Vitrin has nothing to read. Vitrin says so on the Screenshots filter ("Dragged previews aren't saved"). Let the preview finish, or turn off "Show Floating Thumbnail" in the Screenshot app's Options (Shift-Command-5). Also check that Settings, Vitrin has the screenshot folder allowed.

**Nothing new appears in Vitrin.** Check that Vitrin and the capture type are on, the frontmost app is not in the excluded list, and, on macOS versions that ask, that pasteboard access for Nubrix is allowed. Text that looks like a credential is never stored.

**Music is not detected.** Pick the source in Settings, Media. "Now Playing" uses the bundled MediaRemote adapter (run through `/usr/bin/perl`); on macOS versions where macOS has removed that access, Nubrix selects Apple Music instead and you can use the Spotify, Apple Music or YouTube Music controllers. Spotify and Apple Music need the Automation permission (System Settings, Privacy & Security, Automation). YouTube Music needs the desktop app's API server on `localhost:26538`.

**The notch is not visible.** Check Settings, General: "Show on all displays" and "Automatically switch displays" decide which display shows it. On a Mac without a notch the bar is a strip at the top centre; its height is set there too. Settings, Media, "Full screen behavior" can hide it while an app is fullscreen. The menu bar icon can be turned off ("Show menu bar icon"); if you hid it, the Settings window may be hard to reach, so check that first.

**The volume and brightness HUDs did not change.** "Replace system HUD" needs Accessibility access for Nubrix's helper (System Settings, Privacy & Security, Accessibility). If access is missing at launch, Nubrix turns the option off.

## Updating

Nubrix has no auto-updater. Update with the method you installed with, then repeat the Gatekeeper step and refresh the hooks:

```sh
brew upgrade --cask nubrix
```

or run the install script again (it installs the latest release), or `git pull && scripts/install-local.sh` for a source install. Then re-run `install-hooks.sh` so the sealed copies match the new version, and open Nubrix again (System Settings, Privacy & Security, "Open Anyway" if it was blocked).

## Uninstall

1. Remove the Nubrix entries (the hooks, `statusLine` and the `permissions.deny` rules for `~/.config/nubrix*`) from `~/.claude/settings.json` first. Otherwise Claude Code keeps trying to run scripts that no longer exist.
2. Quit Nubrix and remove it:
   ```sh
   brew uninstall --cask nubrix
   ```
   `brew uninstall --cask --zap nubrix` additionally removes `~/.config/nubrix`, `~/.config/nubrix-run`, the app container and preferences. Without Homebrew, delete `/Applications/Nubrix.app` and those same folders by hand.
3. Optional: delete the Keychain item `dev.nubrix.github` (Keychain Access) and revoke the GitHub token on github.com.

## Building and contributing

```sh
xcodebuild -project Nubrix.xcodeproj -scheme Nubrix -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS' build
open build/Build/Products/Debug/Nubrix.app
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow, security-sensitive areas and how releases are cut.

## Roadmap

See [docs/nubrix/ROADMAP.md](docs/nubrix/ROADMAP.md).

## License

GNU General Public License v3.0, see [LICENSE](LICENSE). [NOTICE](NOTICE) states that Nubrix is a modified version of boring.notch, which commit it was forked from and who modified it. `LICENSE`, `NOTICE` and `THIRD_PARTY_LICENSES` are also bundled in the app's Resources.

## Credits

- [boring.notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam and its contributors, the project Nubrix is forked from (GPL-3.0)
- Ideas and selected logic for Vitrin from ClipBoardLine (MIT) and Tendedero (MIT)
- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause)
- Every other bundled or linked dependency, with its copyright line and license, is listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES)

## Disclaimer

Nubrix is an independent project. It is not affiliated with, endorsed by or sponsored by Anthropic. Claude and Claude Code are trademarks of Anthropic.
