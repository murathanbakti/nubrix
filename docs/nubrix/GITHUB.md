# GitHub integration in detail

This page explains how Nubrix reads GitHub. For a short overview, see [GitHub integration](../../README.md#github-integration) in the README.

## Token

Nubrix reads GitHub with a **fine-grained, read-only personal access token** that you create for selected repositories (Settings, GitHub, "Create token on GitHub"). It is stored in the macOS Keychain (generic password, service `dev.nubrix.github`, account `token`, accessible after first unlock, this device only) and is never written to preferences, logs or files. With ad hoc signing the Keychain may ask once for access after you update Nubrix.

Token permissions (all Read, everything else No access): Metadata (automatic), Pull requests, Actions, Commit statuses, and optionally Checks. Repository access: only select repositories.

Why this and not something else:

- **Not the `gh` CLI login.** Its token carries broad write scopes (repo, workflow, ...); anything that can read the Keychain item or a hook could push code. A fine-grained token can only read the repositories you tick.
- **Not SSH keys.** They authenticate git over ssh, give full read and write access to every repository of the account, and cannot call the API that lists PRs, reviews and Actions runs.
- The sandboxed app cannot use another tool's credentials anyway; a token that only Nubrix holds can be revoked on github.com without affecting anything else.

## Requests

- `POST /graphql`: one query for your open PRs and your review requests with `statusCheckRollup`, `reviewDecision`, `mergeable`, `isDraft`
- `GET /user`
- `GET /user/repos`: the repositories the token can read, refreshed every 10 minutes
- `GET /repos/{owner}/{repo}/actions/runs?per_page=10` with `If-None-Match` (a 304 costs no rate limit) for at most 10 watched repositories
- Only if GraphQL cannot read the check rollup: `GET /repos/{owner}/{repo}/commits/{sha}/status` and `.../check-runs`

Requests carry `X-GitHub-Api-Version: 2022-11-28`, redirects are never followed and the token only goes to `api.github.com`. `X-RateLimit-Remaining` and `Retry-After` are honoured: below a 25 request reserve, or after a 403/429, Nubrix stops until the reset time.

## Polling

- Every 2 minutes by default.
- Every 30 seconds while the GitHub section is visible, or while a run is in progress on AC power and outside Low Power Mode.
- Every 7.5 minutes when nothing is running and none of your Claude sessions has a GitHub repository.
- Backs off when offline or when requests fail (up to 15 minutes), is paused while the Mac sleeps or is locked and without a token, and refreshes on opening the section.

Watched repositories: the ones the token can read (switch them off in Settings), repositories you add by hand, the repositories of your Claude sessions and of your open PRs.
