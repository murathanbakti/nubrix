# Security Policy

## Supported versions

Only the latest release receives security fixes. Updates are opt-in (Settings, About, Updates), so update with that, with `brew upgrade --cask nubrix` or by running the install script again, then re-run `install-hooks.sh` if Nubrix says the hook copies are old (see the README).

## Reporting a vulnerability

Report vulnerabilities privately through GitHub's private vulnerability reporting: open the repository's [Security tab](https://github.com/murathanbakti/nubrix/security) and choose "Report a vulnerability" (direct link: https://github.com/murathanbakti/nubrix/security/advisories/new). Please do not open a public issue or pull request for a security problem.

Include the affected version, how you installed it, steps to reproduce and the impact. A proof of concept helps. Do not include real secrets or personal data.

Nubrix is maintained by one person. Expect an acknowledgement within about 7 days and a first assessment within about 14 days. Fixes for confirmed issues ship in a new release, and the advisory credits you unless you prefer otherwise. There is no bug bounty.

## Scope

Nubrix runs locally. Areas where reports are most useful:

- the Claude Code hook scripts (`~/.config/nubrix/bin/`, installed by `install-hooks.sh`), the installer and `notchctl`: for example a way to make them run attacker-controlled code, send a token elsewhere or approve a request without the user
- the loopback event server and its authentication (`~/.config/nubrix-run/agent-endpoint`, the bearer token and the HMAC proof of the permission flow)
- the permission approval card: spoofing, click or timing bypasses of the Allow safeguards, missing risk flags
- the XPC helper (`NubrixHelper`, not sandboxed: Accessibility key handling, brightness, the `claude /usage` probe and, when turned on, the read-only reader of the macOS notification database): privilege escalation, command or argument injection, reading anything beyond the fixed result
- sandbox escapes and the entitlements of the app
- the notification database reader and Full Disk Access (reading anything beyond the one database, or leaking notifications of apps you did not tick)
- Vitrin clipboard storage and bypasses of the secret guard (a credential that should have been skipped but was stored), including the excluded-apps and concealed-type handling
- the GitHub token handling (Keychain storage, requests to hosts other than `api.github.com`)
- the release and install path: the install script, the release workflow and the checksums

Out of scope:

- Gatekeeper prompts for ad-hoc signed builds: 0.1.0 and builds you make yourself (this is documented). For 0.1.1 and later, a Gatekeeper warning or a failing signature check is in scope
- problems that need an attacker who already runs code as your user and can read or write your home folder, apart from bypasses of the protections listed above (sealed scripts, deny rules, sandbox)
- Vitrin history not being encrypted at rest (known and documented; it is stored with 0600/0700 permissions)
- the secret guard missing a credential format it does not claim to detect (it is a heuristic); a new detectable format is welcome as a normal issue
- vulnerabilities in Claude Code itself, macOS or Homebrew

Problems in third-party dependencies should be reported to their maintainers. Problems in code inherited from the upstream project (see Credits in the README) may also be relevant upstream.
