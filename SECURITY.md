# Security Policy

## Reporting a vulnerability

There is no private reporting channel yet. Until one exists, open a GitHub issue that says you found a security problem, without exploit details, proof-of-concept code or anything that would help an attacker. The maintainer will reply and arrange a private way to share the details.

## Scope

Nubrix runs locally. Areas where reports are most useful:

- the loopback event server and its token (`~/.config/nubrix/agent-endpoint`)
- Vitrin clipboard storage and the secret guard
- the Claude Code hook script and `notchctl`

Problems in third-party dependencies should be reported to their maintainers. Problems in code inherited from the upstream project (see Credits in the README) may also be relevant upstream.
