# Contributing to Nubrix

Thanks for your interest. Nubrix is a small project maintained by one person, so keep changes focused.

## Before you start

- Search existing issues and pull requests first.
- For anything larger than a bug fix, open an issue to discuss it before writing code.
- Changes to the hook scripts, the local event server, the XPC helper or the installer are security-sensitive; see [Security-sensitive areas](#security-sensitive-areas).

## Requirements

- macOS 14 or later (the app's deployment target) and Xcode 26 or later.
- `shellcheck` for the shell scripts: `brew install shellcheck`.

## Build

```sh
git clone https://github.com/murathanbakti/nubrix.git
cd nubrix
xcodebuild -project Nubrix.xcodeproj -scheme Nubrix -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS' build
open build/Build/Products/Debug/Nubrix.app
```

Use a derived data path of your own (as above, or `~/Library/Caches/Nubrix/DerivedData`) instead of Xcode's default one. That keeps your command line builds, Xcode builds and `scripts/install-local.sh` from fighting over the same build products. `build/` is ignored by git.

To try a Release build the way users get it, run `scripts/install-local.sh --open`. It builds into `~/Library/Caches/Nubrix/DerivedData`, verifies the bundle, installs to `/Applications` and refreshes the sealed hook copies.

`install-local.sh` signs with the first Apple Development (or Developer ID Application) certificate in your Keychain, using `scripts/sign-release.sh` with `NUBRIX_SIGN_LOCAL=1` (no team or timestamp checks). The code identity then stays the same across rebuilds, so Keychain access and permissions such as Full Disk Access, Camera or Accessibility are kept. Without a certificate, or with `NUBRIX_SIGN_IDENTITY=-`, the build is ad-hoc signed and macOS may ask again after each rebuild. `NUBRIX_SIGN_IDENTITY` also takes a certificate name or SHA-1. Never commit a team ID, certificate, `.p12`, `.p8` or provisioning profile: the project keeps `DEVELOPMENT_TEAM` empty, signing identities are picked on each machine, and release signing uses GitHub secrets.

## Where things live

- Nubrix code is in `Nubrix/Features/`. It is a file-system synchronized group in Xcode, so new files are picked up automatically; avoid editing `project.pbxproj` by hand.
- `NubrixHelper/` is the small unsandboxed XPC service (Accessibility key handling, brightness, the `claude /usage` probe and, when turned on, the read-only reader of the macOS notification database).
- `claude-plugin/` holds the Claude Code hook scripts (`claude-plugin/scripts/`) and the status-only plugin manifest. `cli/notchctl` is the CLI. `scripts/` holds the installers and release tooling.
- Files under the rest of `Nubrix/` come from the upstream project (see Credits in the README). Keep edits there small so upstream changes can still be merged. You can see the upstream repository with `git remote -v` (remote `upstream`).
- Docs live in `docs/nubrix/` (roadmap, audit reports, supply chain notes).

## Code style

- Match the surrounding code: naming, formatting, error handling and structure. There is no separate formatter configuration.
- No drive-by refactors or reformatting in a pull request. Unrelated clean-ups belong in their own pull request.
- Do not add comments that only restate the code.
- Shell scripts are `bash` with `set -euo pipefail`, use absolute paths for system tools and must pass `shellcheck -S error`.

## Checks to run

CI (`.github/workflows/build.yml`) builds the app unsigned in Debug and validates the scripts. Run the same checks before you open a pull request:

```sh
for f in claude-plugin/scripts/* cli/notchctl scripts/*.sh; do bash -n "$f"; done
shellcheck -S error claude-plugin/scripts/* cli/notchctl scripts/*.sh
python3 -m json.tool claude-plugin/hooks/hooks.json > /dev/null
python3 -m json.tool claude-plugin/.claude-plugin/plugin.json > /dev/null
```

Then build with the `xcodebuild` command above. If you change anything the UI shows, run the app and try it.

## Tests

Unit tests live in `NubrixTests/`, one folder per feature (`NubrixTests/Clipboard/`, `NubrixTests/Agents/` and so on). The folder is a file-system synchronized group like `Nubrix/Features/`: drop a `.swift` file in and it is compiled into the `NubrixTests` target, with no `project.pbxproj` edit. Tests run inside the Nubrix app (hosted), so use `@testable import Nubrix`. When XCTest is detected the app skips its migration and launch setup (windows, servers, monitors), so a test run never prompts for permissions.

```sh
scripts/run-tests.sh                                  # all tests
scripts/run-tests.sh -only-testing:NubrixTests/SmokeTests
scripts/run-tests.sh /path/to/derived-data            # own derived data path
```

The script wraps `xcodebuild test -scheme NubrixTests -destination 'platform=macOS'`, prints a pass/fail summary and exits non-zero on failure. Anything after the optional derived data path goes to `xcodebuild`.

The default derived data path is `~/Library/Caches/Nubrix/DerivedData-tests`. When you work in several branches or worktrees at once, give each one its own path (for example `~/Library/Caches/Nubrix/DerivedData-tests-<branch>`) so parallel builds do not overwrite each other. Do not put derived data inside `~/Documents` or another synced folder.

The `Nubrix` and `NubrixTests` schemes are shared and committed (`Nubrix.xcodeproj/xcshareddata/xcschemes/`); other schemes stay ignored.

## Security-sensitive areas

Nubrix runs next to Claude Code with your privileges. Take extra care, explain the threat model in the pull request, and expect a slower review for changes to:

- the hook scripts (`claude-plugin/scripts/*`, `cli/notchctl`) and `scripts/install-hooks.sh`: they are installed as sealed read-only copies and run unsandboxed on every Claude Code event. Keep `PATH` pinned, call tools by absolute path, never put tokens on a command line, and keep failing closed (print nothing, exit 0, let Claude Code ask natively).
- the loopback event server and the permission flow (`Nubrix/Features/Agents/`): authentication, the HMAC proof, the approval card and the risk flags.
- `NubrixHelper/` and the XPC protocol: it is not sandboxed, so keep its surface minimal and its inputs validated.
- entitlements and the sandbox exceptions in `Nubrix/*.entitlements`.
- the Vitrin secret guard and anything that stores clipboard content.

Never add telemetry, automatic approval of permission requests, or code that edits `~/.claude/settings.json`. Report vulnerabilities privately, see [SECURITY.md](SECURITY.md).

## Pull requests

- Create a branch from `main`, make the change, and make sure the project builds and the checks above pass.
- Describe what changed and why, and include screenshots or a screen recording for UI changes.
- Link the issue it fixes with `closes #123`.
- Do not include secrets, personal data or build output.

## Upstream changes

Nubrix started as a fork of the project named in the README's Credits section and still tracks it. Upstream changes are merged by the maintainer from the `upstream` remote; please do not open pull requests that only bring in upstream commits.

## Releases (maintainer)

1. Bump `MARKETING_VERSION` in the Xcode project (app and helper targets) and update docs if needed. Merge to `main`.
2. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`. To rerun a release by hand, use Run workflow with the tag selected under "Use workflow from"; runs from a branch stop.
3. The release workflow (`.github/workflows/release.yml`) runs two jobs. `build` compiles the universal app with `scripts/package-release.sh --build-only`, including the Swift packages, with a read-only token and no signing secrets. `release` takes that app, signs and notarizes it with `scripts/package-release.sh --app`, and creates a draft GitHub release with `Nubrix-<version>.zip` and `Nubrix-<version>.zip.sha256`. It never compiles or runs third-party code. It also renders the Homebrew cask as `nubrix.rb`.
4. Check the draft, then publish it.
5. Update the cask in [murathanbakti/homebrew-tap](https://github.com/murathanbakti/homebrew-tap) with the workflow's rendered `nubrix.rb` (`Casks/nubrix.rb`) and push.

### Signing and notarization

Without signing secrets the workflow builds an ad-hoc signed release that is not notarized, as before. With them it re-signs every piece of code in the bundle with a Developer ID Application certificate (hardened runtime, secure timestamp, existing entitlements kept, `get-task-allow` removed), from the inside out: `MediaRemoteAdapterTestClient`, `Lottie.framework`, `MediaRemoteAdapter.framework`, `NubrixHelper.xpc`, then `Nubrix.app`. The hook kit scripts and `notchctl` are sealed by the app signature. It then submits the app with `notarytool`, staples the ticket and checks it with `spctl`. The draft release notes say which kind of build it is.

| Name | Kind | Value |
| --- | --- | --- |
| `DEVELOPER_ID_P12_BASE64` | secret | `base64 -i DeveloperID.p12` of the exported Developer ID Application certificate and its private key |
| `DEVELOPER_ID_P12_PASSWORD` | secret | the password chosen when exporting the `.p12` |
| `NOTARY_API_KEY_P8_BASE64` | secret | `base64 -i AuthKey_<KEYID>.p8` of an App Store Connect API key |
| `NOTARY_API_KEY_ID` | secret | the key ID of that API key |
| `NOTARY_API_ISSUER_ID` | secret | the issuer ID shown above the App Store Connect key list |
| `APPLE_TEAM_ID` | variable | the 10 character team ID that owns the certificate |

The `release` job uses the GitHub environment `release`, which only `v*` tags can deploy to, so the secrets belong there rather than at the repository level. `scripts/setup-release-signing.sh` sets everything up without Keychain Access:

1. `csr` makes a private key and a certificate signing request in `~/.nubrix-signing` (never in the repository). Upload it as a Developer ID Application certificate on developer.apple.com, and create an App Store Connect API key with the Developer role.
2. `environment` creates the `release` environment with its `v*` tag rule.
3. `upload --env release` builds the `.p12` with a random password, checks that macOS can import it, sets the secrets and `APPLE_TEAM_ID` on that environment of the `origin` remote's repository after asking, and deletes copies stored at the repository level.

The private key is imported on the runner as non-extractable, into a temporary keychain that is deleted at the end of the job. Keep a copy of `~/.nubrix-signing` in a password manager or on an encrypted disk, then delete it.

If `DEVELOPER_ID_P12_BASE64` is set, all other entries are required and the workflow stops when one is missing. Locally, `NUBRIX_SIGN_IDENTITY=- scripts/sign-release.sh <app>` runs the same re-signing ad hoc, to test it without a certificate. It re-signs that app in place, so run it on a copy.

There is no auto-updater; users update with `brew upgrade --cask nubrix` or by running the install script again.

## Reporting bugs and requesting features

Use the issue forms. For a bug, include your macOS version, Nubrix version, install method (Homebrew, script or source), Mac model, steps to reproduce, and expected versus actual behavior; for Claude Code related bugs also the Claude Code version. For security problems read [SECURITY.md](SECURITY.md) first.

## License

By contributing you agree that your contribution is licensed under GPL-3.0, the same as the project.
