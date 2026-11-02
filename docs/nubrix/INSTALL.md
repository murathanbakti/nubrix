# Installing Nubrix

Install methods in detail. The short version is in the [README](../../README.md#install).

Each release on [GitHub Releases](https://github.com/murathanbakti/nubrix/releases) has a `Nubrix-<version>.zip` (a universal arm64 and x86_64 `Nubrix.app`) and a `.sha256` checksum, both built by GitHub Actions. From 0.1.1 on, releases are signed with a Developer ID and notarized by Apple, so macOS opens them without a Gatekeeper prompt however you install. 0.1.0 was ad-hoc signed; each release's notes say which kind it is.

## Homebrew (recommended)

```sh
brew tap murathanbakti/tap
brew trust --tap murathanbakti/tap
brew install --cask nubrix
```

`brew trust` is needed because Homebrew 7 only installs from third-party taps you have trusted.

The cask pins the release's SHA-256 and leaves the quarantine flag in place, so Gatekeeper checks the Developer ID signature and Apple's notarization ticket on first launch, as for any other app.

## Install script

```sh
curl -fsSL https://raw.githubusercontent.com/murathanbakti/nubrix/main/scripts/install.sh | bash
```

The script downloads the latest release zip and its `.sha256`, verifies the checksum, the bundle identifier and the code signature, and installs `Nubrix.app` to `/Applications`. Options: `NUBRIX_VERSION` (a specific version), `NUBRIX_INSTALL_DIR` (default `/Applications`) and `NUBRIX_SHA256` (a checksum you copied from the release page, checked as well).

Files downloaded with `curl` carry no quarantine flag, so there is no Gatekeeper prompt; trust rests on HTTPS to GitHub, the checksum and the signature check, and the script tells you whether the version it installed is notarized. Piping a script into a shell runs whatever the server sends, so read it first if you can:

```sh
curl -fsSLO https://raw.githubusercontent.com/murathanbakti/nubrix/main/scripts/install.sh
less install.sh
bash install.sh
```

## From source

```sh
git clone https://github.com/murathanbakti/nubrix.git
cd nubrix
scripts/install-local.sh --open
```

This needs Xcode 26 or later. The script builds Release into `~/Library/Caches/Nubrix/DerivedData`, verifies the bundle (hardened runtime on, no `get-task-allow`, only the expected helper and frameworks), quits a running Nubrix, installs `Nubrix.app` to `/Applications`, runs `scripts/install-hooks.sh` and, with `--open`, starts the app. It stops if a check fails. A build you made yourself opens with no Gatekeeper prompt.

If your Mac has an Apple Development or Developer ID Application certificate (any free Apple account signed in to Xcode creates one), the script signs the app with it, so macOS keeps Keychain access and permissions across rebuilds. The first time, macOS may ask to let `codesign` use the key; choose Always Allow. Without a certificate the app is signed ad hoc. Set `NUBRIX_SIGN_IDENTITY` to a certificate name or SHA-1 to choose one, or to `-` to force ad-hoc signing. The certificate stays in your Keychain; nothing about it is written to the repository.

## Next steps

- The first launch asks for no permissions. Calendar, camera, Accessibility and Full Disk Access are each asked the first time you use the feature that needs them. See [Permissions](PERMISSIONS-AND-SETTINGS.md#permissions).
- Connect Claude Code: [Claude Code setup](../../README.md#claude-code-setup).
- A release that is not notarized (0.1.0) and was downloaded with a browser: [First launch and Gatekeeper](../../README.md#first-launch-and-gatekeeper).
- [Updating](../../README.md#updating) and [Uninstall](../../README.md#uninstall).
