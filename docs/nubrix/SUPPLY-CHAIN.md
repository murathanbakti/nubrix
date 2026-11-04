# Supply chain

This page covers the two pieces of third-party binary code that ship in the app: the committed `mediaremote-adapter` binaries and Sparkle.

## Committed `mediaremote-adapter` binaries

Nubrix reads system now-playing data through [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause, see `THIRD_PARTY_LICENSES`). The built artifacts are committed in `mediaremote-adapter/`. They are built from upstream tag `v0.7.2` (commit `dc3ff1740e2035a2490ec67d3b33322449af780a`) by `scripts/build-mediaremote-adapter.sh`, for arm64 and x86_64 with a macOS 14.0 deployment target.

The binaries committed before 2026-11-02 had no recorded provenance and a macOS 15.0 deployment target. They were identified as `v0.7.2`: a rebuild of that tag has the same exported, imported and local symbols, the same strings and the same `__text` size (44,628 bytes on arm64) as the old framework. The test client differs only by the runtime availability check that a macOS 14 target adds.

## What is committed

| File | Use | SHA-256 |
|---|---|---|
| `mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter` | embedded in `Contents/Frameworks`, loaded by `/usr/bin/perl` | `ac830b1ddb860875ac9dc52e97cc246f4c79ba422e971fed825aea1a7ce7ce42` |
| `mediaremote-adapter/MediaRemoteAdapterTestClient` | copied into `Contents/Resources`, run by `helpers/MediaChecker.swift` | `dac9ee90c28e7dda39849beeae25437828e1599a35378a00469d2dc30cbdf8c1` |
| `mediaremote-adapter/mediaremote-adapter.pl` | Perl loader used by `NowPlayingController.swift` and `MediaChecker.swift` | `9ac5ed4532ad78431a85dd30e353efeca84391c4b84c760de74399c09cc2f2ca` |

Both binaries are ad-hoc signed (`com.vandenbe.MediaRemoteAdapter` and `MediaRemoteAdapterTestClient`, no Team ID); the release workflow re-signs them with the Developer ID (see CONTRIBUTING, Signing and notarization). The app does not link the framework; it only embeds it for `/usr/bin/perl`. Linking it would run its load-time constructor in the app, which installs SIGINT and SIGTERM handlers that stop a stream the app never runs, so the app would ignore `kill` and `killall`. Because Release builds run with the hardened runtime, the app carries `com.apple.security.cs.disable-library-validation` (`Nubrix/Nubrix.release.entitlements`) so that dyld accepts this framework. This means the app will load any code-signed library placed at the paths it opens, so the integrity of this directory matters.

## Check the committed files

```sh
shasum -a 256 mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  mediaremote-adapter/MediaRemoteAdapterTestClient mediaremote-adapter/mediaremote-adapter.pl
codesign -dv mediaremote-adapter/MediaRemoteAdapter.framework
```

Compare the output with the table above. A mismatch means the files changed since this note was written.

## Rebuild

```sh
scripts/build-mediaremote-adapter.sh
git diff --stat mediaremote-adapter/
```

The script clones the pinned tag, checks that it resolves to the pinned commit, builds both binaries with `clang` using the source list and frameworks from upstream `CMakeLists.txt`, copies the Perl loader, signs ad hoc and prints the SHA-256 values. It fails if any source uses an API newer than the deployment target without an availability check. Update the table above after a rebuild, and review the upstream diff before moving the pin to a new tag.

## Open items

- Verify the SHA-256 of the framework and test client in a build phase, or build them in CI from the pinned tag.

## Sparkle

Nubrix embeds [Sparkle](https://sparkle-project.org) 2.10.1 for automatic updates (on by default, can be turned off) (license in `THIRD_PARTY_LICENSES`).

- **Package.** Swift Package Manager, `exactVersion` 2.10.1, revision `ab7d71291238df6e0492143b120c9b696a35f603` (`Package.resolved`). The binary framework is a zip whose SHA-256, `4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a`, is enforced by SwiftPM from Sparkle's own `Package.swift`.
- **Mach-O files in the bundle.** Four: `Sparkle`, `Autoupdate`, `Updater.app/Contents/MacOS/Updater` and `XPCServices/Installer.xpc/Contents/MacOS/Installer`, all inside `Contents/Frameworks/Sparkle.framework/Versions/B`. `scripts/verify-bundle.sh` allows exactly these. Sparkle's `Downloader.xpc` is removed by `scripts/strip-sparkle-downloader.sh` when the release is packaged (and by `install-local.sh`), because Nubrix has the network client entitlement and does its own downloading; Debug builds keep it.
- **Signing.** `scripts/sign-release.sh` signs `Installer.xpc`, `Autoupdate`, `Updater.app` and then the framework, from the inside out, without `--deep` and without entitlements. Sparkle's `Autoupdate` ships with a `com.apple.application-identifier` entitlement, which would be a restricted entitlement without a provisioning profile; dropping it matches Sparkle's documented signing commands. The script fails if any Sparkle code still carries entitlements afterwards.
- **CLI tools.** `generate_appcast`, `sign_update` and `generate_keys` come from `Sparkle-2.10.1.tar.xz`, pinned by version and SHA-256 `1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27` in `scripts/sparkle-tools.sh`, and are never cached. They run in the `appcast` job of `release.yml`, which has no Developer ID keychain and no notary key, and where only the EdDSA key file and a write token for the draft release exist; the Sparkle tools themselves run without the GitHub token in their environment.
- **Upgrading Sparkle.** Change both pins (the package version in Xcode and `version` plus `sha256` in `scripts/sparkle-tools.sh`; the CI step "Sparkle pins agree" fails if they differ), read Sparkle's release notes, rebuild the Mach-O inventory in `scripts/verify-bundle.sh` if the layout changed, and rerun `scripts/verify-bundle.sh` on a release build. Check the notary log of the first release after an upgrade for warnings about Sparkle's files.
