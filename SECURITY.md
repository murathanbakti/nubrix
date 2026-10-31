# Security Policy

## Reporting a vulnerability

Report vulnerabilities privately through GitHub's private vulnerability reporting: open the repository's Security tab and choose "Report a vulnerability". Please do not open a public issue or pull request for a security problem. Include the affected version, steps to reproduce and the impact; the maintainer will reply there.

## Scope

Nubrix runs locally. Areas where reports are most useful:

- the loopback event server and its token (`~/.config/nubrix-run/agent-endpoint`)
- Vitrin clipboard storage and the secret guard
- the Claude Code hook scripts (`~/.config/nubrix/bin/`, installed by `scripts/install-hooks.sh`) and `notchctl`

Problems in third-party dependencies should be reported to their maintainers. Problems in code inherited from the upstream project (see Credits in the README) may also be relevant upstream.
