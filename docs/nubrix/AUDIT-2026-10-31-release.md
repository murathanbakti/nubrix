# Nubrix pre-release audit — 2026-10-31

Scope: branch `nubrix` from `d8496aa` (after the first audit's fixes in `be0d2f5` and the later GitHub, transcript-usage and plan-usage commits). Areas: the Claude Code ↔ Nubrix channel (loopback server, approval HMAC, hook scripts, installer, `notchctl`), the XPC helper and the `/usage` probe, entitlements and sandbox, GitHub, Vitrin, release hygiene (git history, licensing, leftovers, dead code) and idle cost (timers, polling, continuous animations, EventKit, GitHub).

Method: read-only review in five parallel areas, harnesses in a scratch directory with a throwaway `HOME` and harness-made tokens (the live token and `~/.claude/settings.json` were not read), then fixes in seven separate branches and one integrated Release build. To check B-1, the installed `claude` CLI was run a few times with the probe's arguments. One of those runs was a deliberate unknown-command test, and it cost about $0.02. The app was not launched by the audit; items that need a running app are listed under [Needs on-device testing](#needs-on-device-testing).

Severities: Critical / High / Medium / Low / Info. "Verified" = reproduced with a harness; "Code" = confirmed by reading the code.

## Summary

- **No Critical findings. Three High findings, all fixed** (R-01 to R-03).
- No secret, token or private key anywhere in the tree or the full git history (2011 commits). The only personal path was in the first audit document and is redacted in the tree.
- Every Medium finding is fixed except S-03, which is accepted: ad-hoc signing, no notarization.
- **Nothing blocks publishing the source.** Before publishing, decide whether to rewrite the 28 Nubrix commits for D-1/D-17 (optional), and push only `nubrix` without tags (D-13).

| Sev | Fixed or confirmed | Accepted |
|---|---|---|
| Critical | 0 | 0 |
| High | 3 | 0 |
| Medium | 16 | 1 |
| Low | 35 | 6 |
| Info | 3 | 8 |

Grouped rows (for example "C-9 / E-6 / E-10") count once.

## Fix commits

| Commit | Area |
|---|---|
| `ca5a9ab` | Plan-usage probe and helper |
| `130a572` | App side of the Claude Code channel, entitlements |
| `2d77373` | Idle cost: stores, EventKit, GitHub, port probes |
| `a18da1c` | Release hygiene: Sparkle, dead code, version, licensing, CI |
| `3498f5e` | Vitrin |
| `2362b62` | Hook scripts, `notchctl`, installer |
| see `git log --oneline d8496aa..` | Continuous animations and music UI; docs and this report |

---

## High

| ID | Area | File | Issue | Status |
|---|---|---|---|---|
| R-01 (A-2) | Hook scripts | `claude-plugin/scripts/*`, `cli/notchctl` | The sealed 0500 hook copies called `curl`, `sed`, `openssl` and `git` through the inherited `$PATH`, where user-writable `/opt/homebrew/bin` comes before `/usr/bin`. A planted `curl` read the token from the header fd and returned a valid HMAC proof, so the permission hook printed `allow` with Nubrix not even running (**Verified**). One approved write outside a project, or any package that installs a `curl`/`sed` shim, would auto-approve every later request in every session. | **Fixed.** Every script pins `PATH=/usr/bin:/bin:/usr/sbin:/sbin` first. `nubrix-permission` calls every tool by absolute path and never uses `jq`. Re-tested: a fake `curl` first in the inherited `PATH` is no longer used. Writes and reads under `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.config/nubrix*` are flagged on the approval card. |
| R-02 (B-4) | Sandbox | `Nubrix.entitlements`, `Nubrix.release.entitlements`, `AgentEventServer.swift` | The sandbox's read-write exception covered all of `~/.config/nubrix/`, including `bin/`, the scripts that Claude Code runs **unsandboxed** on every hook event. A compromise of the sandboxed app (malicious image, media metadata, Lottie JSON) could rewrite `nubrix-permission` and leave the sandbox, approving every request. | **Fixed.** `~/.config/nubrix/` is now read-only for the app; read-write is only `~/.config/nubrix-run/`, where the endpoint file moved (`~/.config/nubrix-run/agent-endpoint`, dir 0700, file 0600). All scripts, `notchctl` and `install-hooks.sh` use the new path; the installer removes the old endpoint file. The printed deny rules cover both directories plus `Read(~/.config/nubrix-run/**)`. |
| R-03 (E-1) | Music | `components/Music/MusicVisualizer.swift` | The spectrum started a 0.3 s main-thread `Timer` that was never invalidated. Each time the music live activity unmounted while music played (every notch open, banner or sneak peek) one timer was orphaned and kept firing until quit. On by default. | **Fixed.** The spectrum is timer-free Core Animation (per-bar keyframe animations, removed when paused or out of a window). |

## Medium

| ID | Area | Issue | Status |
|---|---|---|---|
| A-1 | Hook scripts | The hook sent the raw bearer token to whatever listened on the endpoint's port; the only stale-endpoint check was `kill -0 pid`, which passes for any live same-user pid. After a crash and pid reuse, a port squatter (another macOS user, a sandboxed app with `network.server`) received the token and forged a valid `allow` (**Verified**). | **Fixed.** All scripts check that the pid is a running `…/Nubrix.app/Contents/MacOS/Nubrix` owned by the same uid before sending anything. `nubrix-permission` also requires `lsof` to show that exact pid as the listener on `127.0.0.1:<port>` (20–30 ms). The bind is exclusive, so no other process can hold that port while Nubrix does. A fake server, a shell pid, Finder, a dead pid and an unrelated listener are rejected (**Verified**). |
| A-3 | Approval card | For Bash the card showed and checked only `command`; `dangerouslyDisableSandbox`, `run_in_background` and other keys were invisible, and Edit's `replace_all` was not shown. | **Fixed.** Risks "Runs outside the sandbox", "Runs in background", "Extra tool input" (extra keys shown, sanitized), and a "replace all occurrences" label and risk. |
| B-1 | `/usage` probe | `/usage` is free only while the CLI treats it as a local command. An unknown slash command is sent to the model with all tools; a CLI version without `/usage` would turn every poll into a paid call that uses the plan being watched (a deliberate unknown-command test cost $0.02). | **Fixed.** Arguments add `--tools ""`, `--strict-mcp-config`, `--no-session-persistence`. The stream is inspected as it arrives: the child is killed unless the init event lists `usage` in `slash_commands`, and any result with cost or turns > 0 counts as unsupported. Unsupported stops polling and shows "Update Claude Code to see plan usage". |
| C-1 | Vitrin | The secret guard still stored 15 of 49 sample secrets (passwords in CLI commands, one-line JSON, tokens inside a sentence, several provider prefixes) while Settings said such text was never stored. | **Fixed.** New patterns, inline key/value pass and a per-word scan for short texts. 4 of 49 remain, by design (short password-like words, a 40-hex string, a passphrase, a 6-digit code); false positives unchanged; 1 MB adversarial input stays under ~0.4 s, and input is capped at 256 K characters. Settings text now reads "Text that looks like a password, key or token is skipped when detected." |
| D-1 | Docs | The first audit contained the personal path `/Users/<user>/Documents/...` and read as a list of open vulnerabilities. | **Fixed in the tree** (redacted, and it now points to this report). The path remains in history from `11a2bd7`; see [Before publishing](#before-publishing). |
| D-2 | Licensing | `THIRD_PARTY_LICENSES` listed none of the linked SwiftPM packages, and no licence file shipped in the app. | **Fixed.** Every linked package with its copyright and licence text; swift-syntax noted as build-time only; Tendedero credited. LICENSE, NOTICE and THIRD_PARTY_LICENSES are bundled in `Contents/Resources`. |
| D-3 | GPL-3.0 §5a | No notice that the work is modified, with a date. | **Fixed.** New `NOTICE`: fork of boring.notch at `23e7705` (2026-10-30), modifications and copyright lines, welcome-sound credit. |
| D-4 / B-6 | Dead updater | Sparkle was linked but never started, yet shipped `Autoupdate` and `Updater.app`, two mach-lookup sandbox exceptions and installer keys. | **Fixed.** Sparkle, its code, Info.plist keys, the empty `UTImportedTypeDeclarations` and both mach-lookup exceptions are removed. `install-local.sh` expects only Lottie and MediaRemoteAdapter. |
| E-2 / V-1 | Music slider | `TimelineView(.animation)` (forbidden), with an inverted schedule: display rate when paused, 10 Hz with no media; `.drawingGroup()` on the controls. | **Fixed.** Core Animation progress layer; labels tick once per second only while playing; `.drawingGroup()` removed. |
| V-3 | Marquee | `repeatForever` on overflowing titles (visible by default). | **Fixed.** Core Animation marquee, removed when out of a window or not overflowing. |
| E-3 (P-08 regression) | Notch rendering | `lastHookEventAt`/`lastStatusAt` were `@Published` and set on every hook event and status-line post, re-rendering the whole notch per Claude tool call (live: ~1.4 % CPU during tool calls vs 0.3 % idle). | **Fixed.** Plain properties; the info panel still re-reads them every 5 s. |
| E-4 | EventKit | Every calendar change fetched all reminders, including completed history, in two places that discard reminders, with the notch closed. | **Fixed.** `includeReminders` (default false); due-range predicates when reminders are wanted; the Today tile refreshes only while visible. |
| E-5 | `/usage` probe | The Node-based CLI ran every 5–30 min forever, ignoring battery and Low Power Mode. | **Fixed.** No timer polls after 6 h without Claude activity (refresh on notch open and Stop); interval doubled on battery; none in Low Power Mode; child at utility QoS; stops when Claude Code is not installed. |
| S-02 (residual) | Plugin | `hooks.json` still ran `nubrix-permission` from the git checkout when the repo is loaded as a plugin, and README examples used the checkout path. | **Fixed.** The plugin gives status hooks only; approvals need the sealed copies. README examples use `~/.config/nubrix/bin`. |
| S-07 (residual) | Click integrity | The arming delay used only `.allowsHitTesting`, so an accessibility press could bypass it; synthetic clicks were accepted; "Allow anyway" appeared armed under the cursor. | **Fixed.** `.disabled(!enabled)`; Allow requires a left mouse up from the HID event source; "Allow anyway" re-arms for 0.5 s; the store refuses `allow` within 0.7 s of first display. |
| S-11 (residual) | Hung app | `/v1/ping` was answered off the main thread, so a hung app still held each request for the full wait. | **Fixed.** Ping replies only after a main-actor hop (0.5 s deadline); a permission hold answers `none` if the main actor does not take it within 1 s. |
| S-03 (residual) | Signing | Hardened runtime is on and `get-task-allow` is gone, but the app is ad-hoc signed and needs `disable-library-validation` for the ad-hoc `MediaRemoteAdapter.framework`. TCC grants and the Keychain ACL follow a cdhash that changes with each build. | **Accepted.** No paid Apple Developer account, so no Developer ID or notarization. Hardened runtime still blocks `DYLD_*` injection and debugger attach. Revisit if a signing identity becomes available (then also B-11). |

## Low

| ID | Area | Issue | Status |
|---|---|---|---|
| A-4 | Approval card | Read/Glob/Grep of sensitive paths (including the endpoint token) were green. | **Fixed** ("Reads a sensitive file"). |
| A-5 | Installer | `install-hooks.sh` said "already configured" without checking `nubrix-permission` or the deny rules. | **Fixed**; warns loudly when settings still run scripts from a checkout. |
| A-6 | Display | Session detail, project name and `notchctl` text were not sanitized for bidi/zero-width/control characters. | **Fixed.** |
| A-7 | Server | 16 idle connections, 5 s each, could keep the server full. | **Fixed.** 1 s head timeout, unauthenticated heads capped at 12 of 16. |
| A-8 | Status line | Directory names with escape sequences were printed raw (OSC 52 verified in output). | **Fixed.** C0, DEL and C1 stripped. |
| A-9 | Server | Any instance deleted the shared endpoint file on start/stop. | **Fixed.** Only its own (or a dead pid's) file. |
| S-14 (residual) | `notchctl` | Honoured `NUBRIX_ENDPOINT_FILE` unconditionally, no owner/mode check. | **Fixed.** Only with `NUBRIX_DEV=1`; same checks as the hooks. |
| B-2 / B-3 | `/usage` probe | Each probe started the user's claude.ai MCP connectors and left a transcript folder in `~/.claude/projects` (6 already today). | **Fixed** by the B-1 flags; the helper removes earlier `-T-nubrix-usage-XXXXXX` folders once per launch (real directories owned by the user only). |
| B-5 | `/usage` probe | Stop events ignored failure backoff. | **Fixed.** |
| P-13 | Port probes | 13 TCP handshakes every 5 s while the Dev section is visible; port 5000 labelled "Flask". | **Fixed.** 15 s with tolerance; "AirPlay / Flask". |
| B-7 (S-21) | XPC | The helper accepted any connection. | **Fixed.** `setCodeSigningRequirement("identifier \"dev.nubrix.app\"")`. |
| B-10 / E-11 | GitHub | One shared rate-limit bucket for GraphQL and REST, 10 concurrent run requests, 120 s polling while hidden, no offline/battery backoff. | **Fixed.** Per-resource limits, serial runs, exponential backoff to 15 min, paused offline, 30 s only while visible (or a run is active on AC), 7.5 min when idle. |
| B-12 | Lyrics | lrclib query not encoded with `URLQueryItem`. | **Fixed.** |
| C-2 | Vitrin | Source attribution ignored `org.nspasteboard.source`; four password managers and four legacy marker types missing. | **Fixed.** |
| C-3 | Vitrin | Text with a NUL was stored cut off (**Verified**). | **Fixed.** Explicit byte length. |
| C-4 | Vitrin | A failed FTS secure-delete migration was never retried. | **Fixed.** Version set only on success; re-asserted every start. |
| C-5 | Vitrin | A 16 MB JPEG became a 55 MB PNG; no total size limit. | **Fixed.** Downscale above 24 MP, reject oversized, 1 GB byte budget (schema v2, idempotent backfill). |
| C-6 (S-16) | Vitrin | The panel showed in screen sharing by default. | **Fixed.** "Hide Vitrin from screen sharing", default on, applied live. |
| C-7 | Vitrin | Lowering retention took effect up to an hour later. | **Fixed.** |
| C-8 | Vitrin | Lazy TIFF decode/encode on main when pasting images. | **Fixed.** PNG only. |
| C-9 / E-6 / E-10 (P-03, P-14) | Vitrin | Pasteboard reads with capture off; 0.5 s poll while locked/asleep; screenshot folder listing on main. | **Fixed.** |
| C-10 (P-15) | Vitrin | No index for trim; four `COUNT(*)` per sweep. | **Fixed.** |
| D-5 | Packages | swift-collections and Pow unused; MacroVisionKit listed three times. | **Fixed.** |
| D-6 | Dead code | 13 unused Swift files (~1.5k lines) and an unused Metal shader. | **Fixed.** |
| D-7 | Assets | Unused asset sets, one a Google Chrome icon. | **Fixed.** |
| D-9 | Metadata | Upstream version 2.7.3; bug form describing missing features; `productName = dynamicNotch`. | **Fixed.** 0.1.0 (1); nothing compares versions. |
| D-12 | Docs | LottieFiles download missing from Privacy; install steps ran code from the checkout; wrong paths in ROADMAP; no private reporting channel. | **Fixed** (README, `cli/README.md`, ROADMAP, SECURITY). `git clone <repository-url>` stays a placeholder until the repo exists. |
| D-14 | `.github` | Unrecognised PR template name; deprecated issue templates. | **Fixed.** |
| D-15 | `.gitignore` | No patterns for `.env*`, certificates, sqlite, local Claude settings. | **Fixed.** |
| S-19 | CI | No `-onlyUsePackageVersionsFromResolvedFile` in the build job; no shellcheck. | **Fixed.** shellcheck (`-S error`) runs in the existing ubuntu job; it was not run locally (not installed), so the first CI run may report findings. |
| P-11 | Drag monitor | Global drag monitors installed even with the shelf off. | **Fixed.** |
| E-7 / E-12 | Agents | The 60 s sweep always re-rendered; the usage ledger was copied per turn. | **Fixed.** |
| E-8 | Notch rendering | `ContentView` observed three managers it never reads; `timestampDate` set unguarded. | **Fixed.** |
| E-9 | Meetings | The minute timer ran without calendar access and ticked with nothing to show. | **Fixed.** Armed after the access check, next fire at the next relevant time, 1 s tolerance. |
| V-2 / V-5 / V-6 | Animations | Lyrics `TimelineView(.animation)`, face blink timer, Lottie loop running while paused (all off by default). | **Fixed.** Lyrics wake once per line, the blink is a CA keyframe, Lottie uses the Core Animation engine and pauses with the music. The Lottie JSON is still downloaded from LottieFiles when the built-in visualizer is off (listed in README Privacy). |
| A-2 (part) | Integrity | The app does not check the sealed scripts against a bundled copy. | **Accepted.** After R-01/R-02 the app cannot change them and they do not trust `$PATH`; detection only. Possible follow-up. |
| B-8 | `/usage` probe | On timeout, grandchildren of the CLI survive and a reader thread can stay blocked. | **Accepted.** `--strict-mcp-config` and `--tools ""` leave no grandchildren in practice; changing the blocking read is not worth the risk now. |
| C-1 (rest) | Vitrin | 4 of 49 samples (short passwords, 40-hex, passphrase, 6-digit code) are still stored. | **Accepted.** Catching them causes false positives on ordinary words, hashes and numbers. |
| D-10 | Strings | Stale upstream entries in `Localizable.xcstrings`; some Turkish strings outside the catalog. | **Accepted.** Cosmetic; clean up in Xcode later. |
| D-11 | Camera | Two capture stacks (upstream in-notch mirror and Nubrix hand mirror). | **Accepted.** Both work; merging them is a feature change. |
| E-4 (rest) | EventKit | `CalendarManager` reloads the calendar list on each change. | **Accepted.** Cheap, and debounced. |

## Info

| ID | Note | Status |
|---|---|---|
| A-10 | Transcript reading sends only numbers and cleaned ids; the path must be a non-symlinked `.jsonl` under the physical `~/.claude`. **Verified** with secret-laden, symlinked and out-of-tree transcripts. | Confirmed |
| B-7 (methods) | No helper method reads files, runs caller-supplied commands or performs AX actions. | Confirmed |
| B-9 | The probe's minimal environment ignores `CLAUDE_CONFIG_DIR` and proxy/CA variables; such setups see no plan usage. | Accepted (documented in README) |
| B-11 | The GitHub token is in the legacy file keychain (not synchronizable, never logged or shown; host pinned, redirects refused). | Accepted (needs a team identity, see S-03) |
| D-8 | `Nubrix/nubrix-hello.m4a` is upstream's welcome sound. | Accepted (credited in NOTICE) |
| D-13 | Local `main` is stale upstream and there are 28 upstream tags. | Accepted (publishing instruction below) |
| D-16 | Upstream history contains contributors' Team IDs, emails and one path, all already public upstream. | Accepted |
| D-17 | The 28 Nubrix commits carry the author's Gmail address. | Accepted (optional rewrite below) |
| D-18 | The rename is clean; every remaining "boring"/"TheBoredTeam" hit is credit, migration or the MacroVisionKit fork URL. | Confirmed |
| D-19 | `mediaremote-adapter/` binaries have no recorded source build (see `SUPPLY-CHAIN.md`). | Accepted |
| — | A full rebuild shows Swift 6 concurrency and unused-value warnings in unchanged upstream files (`SpotifyController`, `YouTubeMusicController`, `XPCHelperClient`, `SparkleView`, Shelf). No warning comes from audit changes. | Accepted |

## First audit: status of every finding

| ID | Status |
|---|---|
| S-01 | Fixed (HMAC in `be0d2f5`; server verification in this audit, A-1) |
| S-02 | Fixed (sealed copies in `be0d2f5`; plugin/README residual and PATH in this audit) |
| S-03 | Partly fixed, rest accepted (see Medium) |
| S-04 | Fixed (residuals A-3, A-6 fixed) |
| S-05 | Fixed (token never in argv; verified with `ps`) |
| S-06 | Fixed |
| S-07 | Fixed (residual fixed in this audit) |
| S-08 | Fixed (C-1) |
| S-09 | Fixed (secure-delete verified on a schema copy; store excluded from backups) |
| S-10 | Fixed |
| S-11 | Fixed (residual fixed in this audit) |
| S-12 | Fixed (residual A-7 fixed) |
| S-13 | Fixed |
| S-14 | Fixed (`notchctl` residual fixed) |
| S-15 | Fixed |
| S-16 | Fixed (C-6) |
| S-17 | Fixed (ATS and document scope in `be0d2f5`; Sparkle in this audit. The generic `automation.apple-events` entitlement stays: hardened runtime needs it) |
| S-18 | Accepted (D-19) |
| S-19 | Fixed |
| S-20 | Info, unchanged (no keystroke capture) |
| S-21 | Fixed (XPC requirement, B-7) |
| P-01, P-02, P-04, P-05, P-06, P-09, P-12 | Fixed |
| P-03, P-14, P-15 | Fixed (residuals in this audit) |
| P-07 | Fixed |
| P-08 | Fixed (regression E-3 fixed) |
| P-10 | Fixed (all continuous animations now Core Animation) |
| P-11, P-13 | Fixed |

## Continuous-animation rule

No `repeatForever`, no repeating `symbolEffect`, no `TimelineView(.animation)` remains outside `Features/Shell/NotchGooCanvas.swift`, which runs only during transitions. One-shot `.contentTransition(.symbolEffect)` uses remain (allowed).

## Before publishing

1. **Pushing:** push only this branch, for example `git push origin nubrix:main`, and no tags (`--all`, `--tags` and `--mirror` would publish upstream's stale `main` and 28 release tags as if they were Nubrix's).
2. **Optional history rewrite** (only 28 commits sit on the fork point `23e7705`): `git filter-repo` limited to `23e7705..nubrix` can redact the path in `11a2bd7`'s audit document (D-1) and switch the author email to a GitHub noreply address (D-17). Both are low value; skip unless the email should stay private.
3. **GitHub settings:** enable Private Vulnerability Reporting (SECURITY.md points to it) and Dependabot security alerts.
4. **README:** replace `git clone <repository-url>`.

## After updating (on this Mac)

1. Run `scripts/install-local.sh --open`. It also refreshes the sealed hook copies.
2. In `~/.claude/settings.json` add the new deny rules: `Edit`/`Write` for `~/.config/nubrix-run/**` and `Read(~/.config/nubrix-run/**)`. The installer prints the snippet until they are there.
3. Granted permissions (Calendar, Camera, Accessibility, Keychain item) may have to be confirmed again because of the new build.

## Needs on-device testing

1. Click Allow on a real permission prompt with a mouse and with the trackpad. It should work. A press from Accessibility Inspector or `osascript` should do nothing.
2. Hooks, the status line and `notchctl` reach the new endpoint (`~/.config/nubrix-run/agent-endpoint`) and the info panel shows everything connected.
3. Plan usage still shows on Home and in the Claude tab with the new flags. On `claude` 2.1.286 the auditor confirmed that `/usage` returns the report with them.
4. Vitrin opens an existing history after the schema v2 migration, and copying an image pastes into Preview, Slack and a browser (PNG only now).
5. The music spectrum, the slider, the marquee and lyrics look as before. Open and close the notch several times while music plays, then check CPU in Activity Monitor (R-03).
6. Vitrin is hidden in a screen recording; the toggle works live.
7. GitHub tab: the Actions list still fills (serial run requests) and offline mode shows "Offline" and recovers.
