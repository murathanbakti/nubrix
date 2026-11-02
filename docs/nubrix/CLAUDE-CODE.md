# Claude Code integration in detail

This page explains how Nubrix gets Claude Code session status, usage numbers and permission requests, and what each part reads, sends and checks. For setup, see [Claude Code setup](../../README.md#claude-code-setup) in the README.

Contents: [Sealed hook scripts](#why-sealed-copies) · [Plugin](#plugin-status-only-source-checkout) · [Source label, branch and jump](#source-label-branch-and-jump) · [Usage, context and cost](#usage-context-and-cost) · [Approving permissions from the notch](#approving-permissions-from-the-notch)

## Why sealed copies

Hooks run with your full privileges in every Claude Code session, so they must not live in a folder that Claude, a `git checkout` or a pull request can rewrite. That is why the installer makes read-only copies outside any repository: it copies `nubrix-hook`, `nubrix-permission`, `nubrix-statusline` and `notchctl` to `~/.config/nubrix/bin/` (directories mode 0700, files 0500), can be run again at any time, and warns if your settings still point into a source checkout.

- **Two folders, two jobs.** `~/.config/nubrix/` holds the sealed scripts; the sandboxed app can only read it. `~/.config/nubrix-run/` holds `agent-endpoint` (`port token pid`, file 0600 in a 0700 directory) and is the only place under `~/.config` the app can write. So even a compromised app cannot modify the scripts Claude Code runs.
- **Deny rules.** The settings snippet adds `permissions.deny` rules so Claude cannot edit the scripts or read the token: `Edit` and `Write` for `~/.config/nubrix/**` and `~/.config/nubrix-run/**`, and `Read(~/.config/nubrix-run/**)`.
- **What the scripts check.** They pin `PATH` to the system directories and call every tool by absolute path. Before sending the token they check that the process id in the endpoint file is a running `Nubrix.app` owned by you, and ignore the file otherwise. The permission hook additionally checks with `lsof` that this process is the one listening on the port, and verifies an HMAC reply proof (see [Approving permissions from the notch](#approving-permissions-from-the-notch)).
- `NUBRIX_ENDPOINT_FILE` and `NUBRIX_PERMISSION_WAIT` are only honoured when `NUBRIX_DEV=1` is set (tests); a project's `.claude/settings.json` cannot redirect the hooks.
- Large `tool_response` and file contents are stripped by `nubrix-hook` before forwarding (with the system `jq`; without it, events over 256 KB are reduced to session, tool and event name).

## Plugin (status only, source checkout)

For a quick look without touching your settings you can load the plugin from a clone of the repository:

```sh
claude --plugin-dir /path/to/nubrix/claude-plugin
```

It registers `nubrix-hook` for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, PermissionDenied, Notification, Stop, StopFailure and SessionEnd. It has no `nubrix-permission` hook: notch approvals work only with the sealed copies. The plugin runs the scripts from the checkout, so prefer the sealed install for daily use.

## Source label, branch and jump

The hook script sends the app that launched Claude Code (`CLAUDE_CODE_ENTRYPOINT`, `__CFBundleIdentifier`, `TERM_PROGRAM`) and, on SessionStart, UserPromptSubmit and Stop, the current git branch and the GitHub repository (`owner/repo`, parsed from `git remote get-url origin`; only `github.com` https, ssh and `git@github.com:` remotes count, credentials in the URL are never forwarded, anything else sends nothing). Nothing else is read from your project.

## Usage, context and cost

Where the numbers come from depends on how you run Claude Code:

| | Desktop app and VS Code | Terminal |
|---|---|---|
| Context %, tokens, cost estimate | transcript, via the event hook | transcript, via the event hook |
| Context %, cost (exact) | not available | status line |
| 5h / 7d rate limits | official plan usage (`claude /usage`) | official plan usage, or the status line |

### Transcript (works everywhere)

The desktop app never runs the `statusLine` command, but every hook payload names the session transcript. On `Stop` (and `SubagentStop`, if you configure that hook; the setup snippet does not), `nubrix-hook` reads only the tail of that file and sends Nubrix a handful of numbers:

- the context size (`input + cache_creation + cache_read` tokens of the last assistant message)
- the token totals of the turn since your last prompt
- the model id and the id of the last message (to avoid counting a turn twice)

No message text is read into the request or sent.

How much is read: first the last 6 MB and 400 relevant lines; only when the turn started before that, a second pass over the last 24 MB and 4000 relevant lines; never more, and never the whole file of a larger transcript. It needs the system `jq`. The transcript must be a regular `.jsonl` file you own, not a symlink, under `~/.claude/`; anything else is ignored. A turn longer than about 4000 transcript lines is not counted (the context figure still is). The extra work is roughly 60 to 80 ms per `Stop` on a 20 MB transcript, and about 0.4 s when the second pass is needed, in the background.

What Nubrix shows and keeps:

- Per session, a context bar with the percentage and the session's tokens (input, output and cache writes; cache reads are not counted).
- In the header, `Today · 1.2M tokens · ~$4.20`, reset at local midnight.
- Each counted turn is kept in a small usage ledger, `Application Support/Nubrix/claude-usage.json` (mode 0600, written atomically at most every 5 s, pruned to 7 days and 20,000 records). A record holds only the time, a short hash of the session id, the token count, the estimated cost and the model id; no prompts, paths, project names or content. The Today line is computed from that ledger.
- The context window is taken from the status line when known; otherwise it is 1M when the model id contains `[1m]` or when the context already exceeds 200k, and 200k otherwise.
- Costs are marked `~` because they are estimates from list prices per million tokens built into [`AgentUsage.swift`](../../Nubrix/Features/Agents/AgentUsage.swift) (cache writes at 1.25x input, cache reads as listed or 0.1x input). Plans, discounts and unknown models are not reflected. A status line cost, when present, replaces the estimate.

### Status line (terminal only)

Claude Code passes exact context usage, cost and rate limits only to the status line command. `nubrix-statusline` forwards that JSON to Nubrix in the background (it never delays the status line) and prints a compact line: `project · branch · model · ctx 42% · $1.23`. It works without `jq`; if `jq` is installed it is used for parsing.

- While a session sends status line updates, its percentage comes from there; otherwise from the transcript.
- The context bar is green below 60%, orange up to 85% and red above. When a session crosses 85% Nubrix shows a banner and an inbox entry ("Context 87% - consider /compact").
- The status line's 5-hour and 7-day limits are a secondary source for the plan meters described below (claude.ai Pro, Max and Ultra subscribers, after the first response).

### Official plan usage (`claude /usage`)

The primary source for the session (5-hour) and weekly meters is the number Claude itself reports: the helper (`NubrixHelper`, the unsandboxed XPC service) runs the installed Claude Code CLI as `claude /usage`. This is a local command, not a model call (`total_cost_usd` 0, no turns), so it costs no tokens and does not count against your limits. It relies on the experimental `usage_report` that Claude Code attaches to that reply, so a future Claude Code version may change or drop it; the card then falls back to the other sources.

- **The Claude CLI must be signed in.** Run `claude auth login` once in a terminal. If `/usage` returns no report, the helper also runs `claude auth status`; when that says you are signed out, the card shows "Claude sign-in needed: claude auth login" instead of silently falling back to transcript tokens. API-key logins and accounts without plan limits show "Plan usage needs a Claude subscription".
- **Which binary.** Only fixed locations are tried, in order: `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`, `~/.local/bin/claude`, `~/.claude/local/claude` (real home from the system user database). No `PATH` lookup, nothing user supplied. Symlinks are resolved; the entry and its target must be regular files owned by you or root, executable and not group- or world-writable, and the target's folder must be owned by you or root and not world-writable. Otherwise Claude is treated as not installed ("Claude Code not found").
- **How it runs.** Fixed arguments (`claude -p --output-format stream-json --verbose --setting-sources project --tools "" --strict-mcp-config --no-session-persistence /usage`), stdin `/dev/null`, working directory a fresh empty temporary folder (removed afterwards), a minimal environment (`HOME`, `USER`, `LOGNAME`, `PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin`, `LANG`), a 30 s timeout and at most 1 MB of output read. The command is started as a short-lived launchd job (`dev.nubrix.usage-probe.*`, removed afterwards) so that the Claude CLI can read its own login from the macOS Keychain; if launchd refuses the job, the helper falls back to spawning the process directly. It uses the Claude Code login in `~/.claude`; `CLAUDE_CONFIG_DIR` and proxy variables are ignored. No tools and no MCP servers are loaded. `--setting-sources project` with an empty folder means no user or project settings are loaded, so your own Claude Code hooks (including `nubrix-hook`) do not fire and no phantom session appears in Nubrix.
- **Self-check.** The probe stops itself and the card shows "Update Claude Code to see plan usage" if the CLI does not list `/usage` as a command or reports any cost or turn. While `/usage` stays a local command it is free.
- **What leaves the helper.** Only a small list of `{kind, group, percent, resetsAt, isActive, severity, scopeModel}` plus the fetch time, or one of `notInstalled`, `notSubscriber` (API-key login or no limits reported), `signedOut`, `unsupported`, `timeout`, `failed`. Raw output is never returned or logged. The app keeps the last good result (numbers and times only) in its preferences so the card shows something after a relaunch; it is marked as stale in the tooltip after 30 minutes.
- **When it runs.** About every 5 minutes while a Claude Code session was active in the last hour, otherwise every 30 minutes. The interval doubles on battery, and the timer does not poll in Low Power Mode. After 6 hours without Claude activity timer polling stops; the numbers still refresh when the notch opens on Home or the Claude tab (if the data is older than 2 minutes) and once after a `Stop` hook event (at most every 2 minutes). Paused while the Mac sleeps or is locked. Errors back off exponentially (5, 10, 20, then 30 minutes). Views are only updated when the numbers change.
- **Alerts.** When the session or weekly value first crosses 80% and again 95% in a window, Nubrix shows a closed-notch banner and an inbox entry ("Claude Code" source), once per window (keyed by its reset time).
- **Setting.** Settings, Notifications, Claude Code: "Show official plan usage (runs `claude /usage` in the background)" (on by default). Off means nothing is run and the card uses the status line limits or the transcript estimate.

### Home tab card

Next to the music player the Home tab shows a Claude card with your 5-hour and weekly usage.

- With official plan values it shows a `Session` row (the 5-hour window, as Claude calls it) and a `Week` row with percentage, bar and reset (`45%`, `resets 5:10 PM`), plus, when there is room, the busiest per-model weekly limit above 0% (`Opus 12%`; all of them are in the tooltip).
- When the status line also reports the limits (the 5-hour value within the last 6 hours, the 7-day value within the last 7 days, and its reset time still in the future), whichever source is fresher is used per row. A window whose reset time has passed is dropped.
- When neither official source is available it shows an estimate from the ledger over rolling windows of the last 5 hours and last 7 days: tokens and `~$` cost. Estimates are never shown as a percentage because the plan limit is unknown.
- Hover the card for the source and turn counts; click it to open the Claude tab.
- The card appears when there was any Claude activity in the last 7 days, is replaced by the meeting card while a meeting countdown is showing, refreshes once a minute only while the notch is open, and can be turned off in Settings, Notifications, "Show 5-hour and weekly usage on the Home tab". The labels are shown in Turkish when the system language is Turkish.

## Approving permissions from the notch

`nubrix-permission` is a synchronous `PermissionRequest` hook (the async `nubrix-hook` stays for state). It is installed by the installer and is not part of the plugin. It sends the request to Nubrix and waits for your answer; Nubrix shows the tool and the full command, file or URL with Allow and Deny, and the script turns the answer into the documented `hookSpecificOutput` decision.

The settings entry (printed by the installer) puts the synchronous hook next to the async one:

```json
"PermissionRequest": [
  { "hooks": [
    { "type": "command", "command": "~/.config/nubrix/bin/nubrix-hook", "async": true, "timeout": 5 },
    { "type": "command", "command": "~/.config/nubrix/bin/nubrix-permission", "timeout": 125 }
  ] }
]
```

Rules:

- **The script only trusts a real Nubrix.** It checks that the endpoint's process id is a running `Nubrix.app` of your user and, with `lsof`, that this process is the listener on the port. It then sends a random nonce; Nubrix answers with `HMAC-SHA256(token, nonce|decision|session_id)` (key: the token from the endpoint file) and the script checks it with the system `openssl` before printing allow or deny. Any mismatch, a stale endpoint file or a process that merely listens on the port produces no output, so Claude Code asks in its own dialog. The token is passed to `curl` through a file descriptor, never on the command line.
- **The card shows everything.** The whole command is in a scrollable monospaced box; Write, Edit and MultiEdit also show a scrollable preview of the content or a `-`/`+` diff. The tool's own `description` is labelled "Claude's description".
- **Allow needs a deliberate click.** It only becomes clickable after the card has been on screen for 0.7 s and the pointer has moved over it, and it needs a real hardware mouse click: synthetic clicks and accessibility presses are ignored. Deny is always available.
- **Risky prompts need a second click** ("Allow anyway"). Risk flags: multi-line, long (over 500 characters) or truncated commands; invisible or direction-control characters; `rm -rf`, `sudo`, `git push --force`, `git reset --hard`, `curl | sh`; writes outside the project or to sensitive files (shell profiles, `.envrc`, `.vscode/tasks.json`, CI workflows, `.claude/`, Nubrix's own config folders, ...); reads of sensitive files; a sandbox bypass; a command that runs in the background; extra tool input that the card does not show; `replace_all` edits. Risky input is shown in red.
- **Questions and plans are not shown in the notch.** Claude's own questions (`AskUserQuestion`) and plan approvals (`ExitPlanMode`) need Claude's own interface, so the hook ignores them and the app rejects such payloads. You answer them in the terminal or the Claude desktop app, as before.
- **Locked screen.** Pending prompts are withdrawn when the screen locks, the Mac or its displays sleep, or the user session switches, and the card is never shown on the lock screen. If no notch can show the card (for example a fullscreen app while Settings, Media, "Full screen behavior" hides the notch, or approvals turned off), Nubrix answers immediately and Claude Code asks natively.
- **Nothing is ever approved automatically.** If Nubrix is not running, the toggle is off, no answer arrives in time, or anything is malformed, the script prints nothing and Claude Code asks in its own dialog as before.
- "Open in <app>" brings the source app forward and withdraws the notch prompt so you answer natively. Answering in Claude Code first also withdraws the prompt.
- Up to 5 requests queue ("1 of 3"); requests over 64 KB or beyond the queue are left to Claude Code.
- Wait time: 110 s in the desktop app and VS Code (Claude Code shows its own dialog at the same time and whichever answers first wins), 12 s in a terminal (the hook may hold the terminal dialog back while it waits). A 1 s liveness probe runs first, so a hung Nubrix costs about one second. `NUBRIX_PERMISSION_WAIT` (seconds) only applies with `NUBRIX_DEV=1`.
- Turn it off in Settings, Notifications, "Approve Claude Code permissions from the notch".
