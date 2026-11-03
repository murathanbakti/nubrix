# Plan: Sparkle 2 auto-updates

Status: implementation spec, 2026-11-03. Supersedes [update-mechanism.md](update-mechanism.md) (notify-only checker, B1). Background: [research/update-mechanism.md](../research/update-mechanism.md), Option A.

Owner decisions this spec follows: Sparkle 2 is the only update mechanism; opt-in (nothing is checked or installed until the user turns it on); signed feed; only Developer ID release builds update themselves; appcast built in `release.yml` and served as a release asset behind `releases/latest/download/appcast.xml`; the private key never leaves the owner's keychain except into the GitHub `release` environment.

Everything marked **verified** was checked on 2026-11-03 against the Sparkle 2.10.1 tag, its release assets, the repository at `2b98480` or the live GitHub redirect chain. Sources are listed at the end.

---

## 0. Facts the implementation depends on

| Fact | Value | How verified |
|---|---|---|
| Latest stable Sparkle | **2.10.1**, published 2026-10-25 (2.10.0 2026-09-13; 2.9.6 2026-08-17). macOS 12+ required since 2.10.0 | GitHub releases API |
| SwiftPM | URL `https://github.com/sparkle-project/Sparkle`, product **`Sparkle`**, binary target. Tag `2.10.1` = commit `ab7d71291238df6e0492143b120c9b696a35f603`. Binary zip checksum `4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a` (enforced by SwiftPM from Sparkle's `Package.swift`) | `Package.swift` at the tag, recomputed SHA-256 of the downloaded zip |
| CLI tarball | `https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz`, SHA-256 **`1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27`**, 16,346,336 bytes. Contains `./bin/generate_appcast`, `./bin/sign_update`, `./bin/generate_keys`, `./bin/BinaryDelta`, `./LICENSE`. Tools are universal (x86_64 arm64), ad-hoc signed. The SwiftPM zip has `generate_appcast` and `sign_update` but **not** `generate_keys` | Downloaded, hashed locally (matches GitHub's asset digest), `tar -t`, `lipo -archs` |
| Framework layout | `Sparkle.framework/Versions/B/` (`Current -> B`). Mach-O: `Versions/B/Sparkle`, `Versions/B/Autoupdate`, `Versions/B/Updater.app/Contents/MacOS/Updater`, `Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer`, `Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader`. All universal, ad-hoc, hardened runtime | Inspected the xcframework from the SwiftPM zip |
| Nested entitlements | `Downloader.xpc`: none (not sandboxed since 2.6). **`Autoupdate` carries `com.apple.application-identifier = org.sparkle-project.Sparkle.Autoupdate`.** `sign-release.sh` today re-applies whatever entitlements a binary has, so it would carry this restricted entitlement into a Developer ID signature with no provisioning profile. Sparkle's own manual re-sign commands do not preserve entitlements except on Downloader | `codesign -d --entitlements -` on 2.10.1; sandboxing doc |
| Sandbox | `SUEnableInstallerLauncherService = YES`; no `SUEnableDownloaderService` when the app has `network.client` (Nubrix has it); mach-lookup exception `$(PRODUCT_BUNDLE_IDENTIFIER)-spks` / `-spki` | sandboxing doc |
| Signed feed | `SURequireSignedFeed` needs Sparkle ≥ 2.9 **and** `SUVerifyUpdateBeforeExtraction = YES` (≥ 2.7.3); `startUpdater` fails otherwise. `generate_appcast` signs the whole appcast automatically when the archived app's Info.plist has `SURequireSignedFeed = YES`; `sign_update appcast.xml` also signs/re-signs a feed in place, and `sign_update --verify appcast.xml` verifies it. The signature is an XML comment `<!-- sparkle-signatures:\nedSignature: …\nlength: …\n-->` inside the file, so it does not depend on the host or redirects | customization doc; `SPUUpdater.m` `checkIfConfiguredProperly…`; `generate_appcast/ArchiveItem.swift`, `FeedXML.swift` `writeAppcast`; `sign_update/main.swift`; `common_cli/Signing.swift`; `SPUExtractSignedFeed.m` |
| Keys from CI | `generate_appcast --ed-key-file -` and `sign_update --ed-key-file -` read the base64 private key from stdin (only when no file named `-` exists in the cwd). `generate_keys -x FILE` exports (refuses to overwrite), `-p` prints the public key only, `--account NAME` selects the keychain item | tool sources at the tag |
| Appcast fields | `generate_appcast` uses `CFBundleVersion` → `sparkle:version`, `CFBundleShortVersionString` → `sparkle:shortVersionString`, `LSMinimumSystemVersion` → `sparkle:minimumSystemVersion`, enclosure URL = `--download-url-prefix` + file name. If the private key does not match the app's `SUPublicEDKey` it only prints a warning and **omits** `sparkle:edSignature` (so CI must assert the attribute) | `ArchiveItem.swift`, `Appcast.swift` lines 199–209 |
| No permission prompt | When `SUEnableAutomaticChecks` is present (YES or NO) in Info.plist or user defaults, Sparkle never shows the second-launch permission prompt. With it NO, no check is scheduled and no request is made until the user enables checks or presses Check Now | `SPUUpdater.m` `startUpdateCycle`, `scheduleNextUpdateCheck…` |
| Persistence | `automaticallyChecksForUpdates` / `automaticallyDownloadsUpdates` setters write user defaults `SUEnableAutomaticChecks` / `SUAutomaticallyUpdate`; user defaults override Info.plist. If `SUAllowsAutomaticUpdates` is unset, `allowsAutomaticUpdates` follows `automaticallyChecksForUpdates`, and setting `automaticallyDownloadsUpdates` while checks are off is ignored | `SPUUpdaterSettings.m`, `SUHost.m` `boolForKey` |
| Redirects | `releases/latest/download/appcast.xml` → 302 `github.com/…/releases/download/vX.Y.Z/…` → 302 `release-assets.githubusercontent.com/…` → 200 `application/octet-stream` (observed with `curl -IL` on an existing asset). Sparkle downloads with `NSURLSession` and does not override redirect handling (only its release-notes web views block non-HTTP redirects), so it follows these HTTPS redirects. Signature verification is over the bytes, so it is unaffected | curl; Sparkle source search |
| Drafts | `releases/latest` ignores drafts and prereleases, so the feed appears only when the release is published | GitHub docs |
| User-Agent | `Nubrix/<CFBundleShortVersionString> Sparkle/2.10.1` | `SPUUserAgent+Private.m` |
| Swift actors | `SPUUpdater` and `SPUStandardUserDriver` are `NS_SWIFT_UI_ACTOR` (main actor). `SPUUpdaterDelegate` and `SPUStandardUserDriverDelegate` are not | headers at the tag |
| Installed 0.1.2 | DR `identifier "dev.nubrix.app" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = "399MAAJ7QT"`, secure `Timestamp=` present, `CFBundleVersion` 3, `LSMinimumSystemVersion` 14.0 | `codesign -d -r-`, `PlistBuddy` on `/Applications/Nubrix.app` |

Repository facts:
- Info.plist is generated (`GENERATE_INFOPLIST_FILE = YES`) and merged with `Nubrix/Info.plist` (`INFOPLIST_FILE`) in both app configurations. `INFOPLIST_KEY_*` only covers Apple-defined keys, so the `SU*` keys go into **`Nubrix/Info.plist`** (shared by Debug and Release).
- App target: Debug uses `Nubrix/Nubrix.entitlements` and bundle id `dev.nubrix.app.debug`; Release uses `Nubrix/Nubrix.release.entitlements` and `dev.nubrix.app`. `DEBUG` is set in the project-level Debug `SWIFT_ACTIVE_COMPILATION_CONDITIONS` only.
- `Nubrix/Features` and `NubrixTests` are file-system-synchronized groups: adding or deleting Swift files needs no pbxproj edit.
- No `PBXShellScriptBuildPhase` exists. `ENABLE_USER_SCRIPT_SANDBOXING = YES` at project level (Debug and Release) and on the app's Debug configuration.
- Dynamic package frameworks (Lottie) are embedded by Xcode without an Embed Frameworks entry; the old Sparkle integration (removed in `d26f2d5`) used `kind = exactVersion`.
- `CURRENT_PROJECT_VERSION` = 3 for app and helper; it becomes `sparkle:version`, so it must grow with every release.
- Hook scripts carry **no version**. `install-hooks.sh` copies the four files byte for byte (`cat`) into `~/.config/nubrix/bin/` (mode 500), and the sandboxed app may read `~/.config/nubrix/` (read-only exception). So the app can compare bytes, which is better than a version.

---

## Slice 1: Sparkle tool pin and key setup script

Commit: "Pin Sparkle's CLI tools and add the EdDSA key setup script".

### `scripts/sparkle-tools.sh` (new)

The single place that pins the CLI tools. Used by `setup-sparkle-key.sh`, `make-appcast.sh` and CI.

```bash
#!/bin/bash
set -euo pipefail

version="2.10.1"
sha256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
url="https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"

fail() {
  echo "sparkle-tools: $*" >&2
  exit 1
}

[ $# -eq 1 ] || { echo "usage: $0 <empty-or-new-directory>" >&2; exit 2; }
dest="$1"
[ ! -e "$dest" ] || [ -z "$(ls -A "$dest")" ] || fail "$dest is not empty"
mkdir -p "$dest"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/nubrix-sparkle.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --proto '=https' --tlsv1.2 --retry 3 -o "$tmp/sparkle.tar.xz" "$url" || fail "download failed: $url"
got="$(shasum -a 256 "$tmp/sparkle.tar.xz" | awk '{ print $1 }')"
[ "$got" = "$sha256" ] || fail "SHA-256 mismatch for Sparkle-$version.tar.xz: got $got"

tar -xJf "$tmp/sparkle.tar.xz" -C "$dest" ./bin/generate_appcast ./bin/sign_update ./bin/generate_keys ./LICENSE
for tool in generate_appcast sign_update generate_keys; do
  f="$dest/bin/$tool"
  [ -f "$f" ] && [ ! -L "$f" ] || fail "missing $tool in the archive"
  chmod 755 "$f"
  case " $(lipo -archs "$f") " in
    *" $(uname -m) "*) ;;
    *) fail "$tool has no $(uname -m) slice" ;;
  esac
done
printf '%s\n' "$dest/bin"
```

Notes: no cache (always download and hash); exact member names, so nothing else from the archive lands on disk; `curl` does not set the quarantine attribute, so the ad-hoc signed tools run without a Gatekeeper prompt.

### `scripts/setup-sparkle-key.sh` (new, run by the owner only)

The owner runs it in their own terminal. Claude never runs it and never sees its secret.

```
usage: scripts/setup-sparkle-key.sh [--env NAME] [--account NAME] [--backup] [--yes]
```

Behaviour, in order:
1. `umask 077`; `--env` default `release`, `--account` default `nubrix` (both `^[A-Za-z0-9_.-]+$`). Copy `repository()` and `confirm()` from `setup-release-signing.sh` (same `origin`/`NUBRIX_REPO` logic).
2. `gh auth status` must pass; `gh api repos/$repo/environments/$env` must exist, otherwise fail with "run: scripts/setup-release-signing.sh environment $env".
3. `work="$(mktemp -d …)"`, `trap 'rm -rf "$work"' EXIT`; `tools="$(scripts/sparkle-tools.sh "$work/tools")"`.
4. Key: `pub="$("$tools/generate_keys" --account "$account" -p 2>/dev/null)"`. If that fails (no key), run `"$tools/generate_keys" --account "$account" >/dev/null` (creates the key in the login keychain), then `-p` again. Strip whitespace; require `^[A-Za-z0-9+/]{43}=$`.
5. Guard against accidental rotation: if `Nubrix/Info.plist` already has a non-empty `SUPublicEDKey` that differs from `pub`, fail: "Nubrix/Info.plist has a different SUPublicEDKey. Replacing it stops updates for installed copies (with SUVerifyUpdateBeforeExtraction, Sparkle rotates EdDSA keys only through a Developer ID signed DMG). Import the old key with generate_keys --account nubrix -f <file> instead."
6. Unless `--yes`: `confirm "Store the private key as SPARKLE_ED_PRIVATE_KEY in $repo, environment $env?"`.
7. `"$tools/generate_keys" --account "$account" -x "$work/private-key" >/dev/null`; require non-empty; `gh secret set SPARKLE_ED_PRIVATE_KEY -R "$repo" --env "$env" < "$work/private-key"`; `rm -P "$work/private-key"`. Never `cat`, `echo` or pass the key as an argument.
8. `--backup`: `mkdir -p ~/.nubrix-signing && chmod 700`, then `generate_keys --account "$account" -x ~/.nubrix-signing/sparkle-ed25519.key` (fails if the file already exists, which is desired). Print "Copy ~/.nubrix-signing to your password manager or encrypted disk, as for the Developer ID backup."
9. Print **only** the public key and where it goes:

```
Sparkle public key (SUPublicEDKey): <pub>
Put it in Nubrix/Info.plist:
    <key>SUPublicEDKey</key>
    <string><pub></string>
Private key: login keychain (account nubrix) and GitHub secret SPARKLE_ED_PRIVATE_KEY (environment release).
```

macOS may ask for keychain access on each `-x`/`-p` because the tool runs from a new temporary path each time; allow once, not always.

Public key location: **`Nubrix/Info.plist`, key `SUPublicEDKey`** (one value for Debug and Release; it is not secret and is committed).

Tests for this slice: ShellCheck (`build.yml` already runs `shellcheck -S error scripts/*.sh` and `bash -n`).

**Owner step A happens after this slice** (see Owner steps). Slice 2 needs the public key.

---

## Slice 2: Embed Sparkle and teach the release scripts about it

Commit: "Embed Sparkle 2.10.1 with its sandbox keys, signing and bundle checks". Everything in this slice lands together, because `verify-bundle.sh` rejects the bundle as soon as Sparkle is embedded.

### 2.1 `Nubrix.xcodeproj/project.pbxproj`

Use fresh 24-hex IDs; names below are placeholders.

- `XCRemoteSwiftPackageReference "Sparkle"` (`SPK_REF`): `repositoryURL = "https://github.com/sparkle-project/Sparkle"; requirement = { kind = exactVersion; version = 2.10.1; };`. Add to the project's `packageReferences`.
- `XCSwiftPackageProductDependency` (`SPK_PROD`): `package = SPK_REF; productName = Sparkle;`. Add to the **Nubrix** target's `packageProductDependencies` (not NubrixHelper, not NubrixTests).
- `PBXBuildFile` `SPK_LINK /* Sparkle in Frameworks */ = {isa = PBXBuildFile; productRef = SPK_PROD /* Sparkle */; };` in the app's Frameworks phase `14CEF40F2C5CAED300855D72`.
- `PBXBuildFile` `SPK_EMBED /* Sparkle in Embed Frameworks */ = {isa = PBXBuildFile; productRef = SPK_PROD /* Sparkle */; settings = {ATTRIBUTES = (CodeSignOnCopy, ); }; };` in `B1ECFA062C6FE58A002ACD87 /* Embed Frameworks */`. Explicit embedding makes the order with the strip phase deterministic.
- New `PBXShellScriptBuildPhase` `SPK_STRIP /* Strip Sparkle Downloader */`, appended **last** in the app target's `buildPhases` (after the three Embed Hook Kit phases):
  ```
  isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = ( ); inputPaths = ( ); outputPaths = ( );
  alwaysOutOfDate = 1; name = "Strip Sparkle Downloader"; runOnlyForDeploymentPostprocessing = 0;
  shellPath = /bin/sh; shellScript = "\"${SRCROOT}/scripts/strip-sparkle-downloader.sh\"\n"; showEnvVarsInLog = 0;
  ```
- App target build settings: Debug `14CEF4222C5CAED400855D72` change `ENABLE_USER_SCRIPT_SANDBOXING = YES` to `NO`; Release `14CEF4232C5CAED400855D72` add `ENABLE_USER_SCRIPT_SANDBOXING = NO`. Reason: the phase deletes a directory inside the built product and re-signs it, which the user-script sandbox only allows for declared outputs and which may need keychain access for a developer's Apple Development identity. It is the target's only script phase. Project-level and other targets keep `YES`.
- `Package.resolved`: regenerate with `xcodebuild -resolvePackageDependencies -project Nubrix.xcodeproj` (do not hand-edit `originHash`). Expected new pin: identity `sparkle`, location `https://github.com/sparkle-project/Sparkle`, revision `ab7d71291238df6e0492143b120c9b696a35f603`, version `2.10.1`. Check that no other pin moved.

### 2.2 `scripts/strip-sparkle-downloader.sh` (new)

Nubrix has `network.client`, so Sparkle's Downloader service is never used (sandboxing doc: do not enable it in that case). Removing it keeps the allowlist at four Sparkle Mach-O files and avoids signing a component that would need its entitlements preserved.

```bash
#!/bin/bash
set -euo pipefail

fw="${TARGET_BUILD_DIR:?}/${FRAMEWORKS_FOLDER_PATH:?}/Sparkle.framework"
[ -d "$fw" ] || { echo "error: $fw is missing; this phase must run after Embed Frameworks" >&2; exit 1; }
services="$fw/Versions/B/XPCServices"
[ -d "$services/Installer.xpc" ] || { echo "error: Sparkle Installer.xpc is missing" >&2; exit 1; }

if [ -e "$services/Downloader.xpc" ] || [ -L "$services/Downloader.xpc" ]; then
  rm -rf "$services/Downloader.xpc"
  if [ "${CODE_SIGNING_ALLOWED:-YES}" = YES ]; then
    identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
    [ -n "$identity" ] || identity="-"
    codesign --force --sign "$identity" --timestamp=none --preserve-metadata=identifier,flags "$fw"
  fi
fi

[ "$(ls "$services")" = "Installer.xpc" ] || { echo "error: unexpected Sparkle XPC services: $(ls "$services" | tr '\n' ' ')" >&2; exit 1; }
```

Xcode signs the app itself after all phases, so the app seal covers the re-signed framework. Release signing later re-signs everything (2.6).

### 2.3 `Nubrix/Info.plist`

Add (keep `NSAppTransportSecurity`):

```xml
	<key>SUFeedURL</key>
	<string>https://github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml</string>
	<key>SUPublicEDKey</key>
	<string>OWNER_PUBLIC_KEY_FROM_STEP_A</string>
	<key>SUEnableAutomaticChecks</key>
	<false/>
	<key>SUAutomaticallyUpdate</key>
	<false/>
	<key>SUEnableSystemProfiling</key>
	<false/>
	<key>SUShowReleaseNotes</key>
	<false/>
	<key>SUVerifyUpdateBeforeExtraction</key>
	<true/>
	<key>SURequireSignedFeed</key>
	<true/>
	<key>SUEnableInstallerLauncherService</key>
	<true/>
```

Deliberately **not** set: `SUEnableDownloaderService` (we have `network.client`), `SUAllowsAutomaticUpdates` (so automatic install is only possible while automatic checks are on), `SUScheduledCheckInterval` (default 86 400 s), `SUSignedFeedFailureExpirationInterval` (default 20 days, see Open risks), `SUPromptUserOnFirstLaunch`. `SUShowReleaseNotes = NO` keeps WebKit out (the appcast carries no notes anyway). Do not commit a placeholder: this slice waits for the owner's key.

### 2.4 Entitlements: `Nubrix/Nubrix.entitlements` and `Nubrix/Nubrix.release.entitlements`

Add to both, after the existing `temporary-exception.files…` keys:

```xml
	<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
	<array>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER)-spks</string>
		<string>$(PRODUCT_BUNDLE_IDENTIFIER)-spki</string>
	</array>
```

Xcode expands the variable at signing time, also for the CI's ad-hoc build. Release → `dev.nubrix.app-spks` / `-spki`. Debug → `dev.nubrix.app.debug-spks` / `-spki`: harmless, because the updater never starts in Debug (Slice 3), and if it ever did, Sparkle derives the service names from the host bundle id, so they would still match. `sign-release.sh` re-applies the already expanded entitlements it reads from the built app.

### 2.5 `scripts/verify-bundle.sh`

```bash
expected_frameworks="Lottie.framework MediaRemoteAdapter.framework Sparkle.framework"
expected_macho=(
  "Contents/MacOS/Nubrix"
  "Contents/XPCServices/NubrixHelper.xpc/Contents/MacOS/NubrixHelper"
  "Contents/Frameworks/Lottie.framework/Versions/A/Lottie"
  "Contents/Frameworks/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"
  "Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
  "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
  "Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater"
  "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  "Contents/Resources/MediaRemoteAdapterTestClient"
)
```

(9 files; the `find -type f` scan already ignores the framework's top-level symlinks.) Add after the Frameworks check:

```bash
sparkle="$b/Contents/Frameworks/Sparkle.framework"
[ "$(readlink "$sparkle/Versions/Current")" = "B" ] || fail "Sparkle.framework Versions/Current is not B"
sparkle_xpc="$(find "$sparkle/Versions/B/XPCServices" -mindepth 1 -maxdepth 1 -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//' || true)"
[ "$sparkle_xpc" = "Installer.xpc" ] || fail "Sparkle XPCServices is '$sparkle_xpc', expected 'Installer.xpc'"

plist="$b/Contents/Info.plist"
pl() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null; }
bundle_id="$(pl CFBundleIdentifier)" || fail "no CFBundleIdentifier"
[ "$(pl SUFeedURL || true)" = "https://github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml" ] || fail "SUFeedURL is wrong"
[[ "$(pl SUPublicEDKey || true)" =~ ^[A-Za-z0-9+/]{43}=$ ]] || fail "SUPublicEDKey is missing or not a 32-byte base64 key"
for k in SUEnableInstallerLauncherService SUVerifyUpdateBeforeExtraction SURequireSignedFeed; do
  [ "$(pl "$k" || true)" = true ] || fail "$k must be true"
done
for k in SUEnableAutomaticChecks SUAutomaticallyUpdate SUEnableSystemProfiling SUShowReleaseNotes; do
  [ "$(pl "$k" || true)" = false ] || fail "$k must be false"
done
for k in SUEnableDownloaderService SUAllowsAutomaticUpdates SUScheduledCheckInterval SUSignedFeedFailureExpirationInterval; do
  ! pl "$k" >/dev/null || fail "$k must not be set"
done
```

After the existing app entitlement checks:

```bash
lookups="$(plutil -extract com.apple.security.temporary-exception.mach-lookup.global-name json -o - - <<< "$entitlements" 2>/dev/null || true)"
[ "$lookups" = "[\"$bundle_id-spks\",\"$bundle_id-spki\"]" ] || fail "mach-lookup exception is '$lookups', expected $bundle_id-spks and $bundle_id-spki"
```

(Run this on the app's `$entitlements` before the variable is reused for the helper.)

### 2.6 `scripts/sign-release.sh`

1. `sign()` gets an optional second argument: `sign <target> [keep_entitlements]`, default `1`. When `0`, skip the `codesign -d --entitlements` extraction and pass no `--entitlements`. Everything else (runtime, timestamp, keychain) stays.
2. New function, inside-out, no `--deep`:

```bash
sign_sparkle() {
  local fw="$1" v="$1/Versions/B" n
  [ -d "$v" ] || fail "Sparkle.framework has no Versions/B"
  [ ! -e "$v/XPCServices/Downloader.xpc" ] || fail "Sparkle Downloader.xpc must be stripped at build time"
  for n in "$v/XPCServices/Installer.xpc" "$v/Autoupdate" "$v/Updater.app"; do
    [ -e "$n" ] || fail "missing ${n#"$app"/}"
    sign "$n" 0
  done
  sign "$fw" 0
}
```

3. Frameworks loop:

```bash
for fw in "$app"/Contents/Frameworks/*.framework "$app"/Contents/Frameworks/*.dylib; do
  case "$(basename "$fw")" in
    Sparkle.framework) sign_sparkle "$fw" ;;
    *) sign "$fw" ;;
  esac
done
```

Passing no entitlements strips Autoupdate's `com.apple.application-identifier`, matching Sparkle's documented commands (Downloader is the only Sparkle part whose entitlements would be preserved, and it is gone).

4. In the final per-Mach-O loop add:

```bash
case "$f" in
  "$app"/Contents/Frameworks/Sparkle.framework/*)
    ! grep -q '<key>' <<< "$entitlements" || fail "Sparkle code must carry no entitlements: ${f#"$app"/}"
    ;;
esac
```

The existing loop already enforces runtime, Developer ID authority, team and secure timestamp for every Mach-O, so the four Sparkle files are covered.

### 2.7 `scripts/package-release.sh`

- `check_app`: replace the hard-coded binaries list and the `Versions/A` loop with a scan of every Mach-O, so `Versions/B` and nested helpers are checked too:

```bash
  local bin archs arch
  while IFS= read -r -d '' bin; do
    case "$(file -b "$bin")" in Mach-O*) ;; *) continue ;; esac
    archs="$(lipo -archs "$bin")"
    for arch in arm64 x86_64; do
      case " $archs " in
        *" $arch "*) ;;
        *) fail "${bin#"$app"/} lacks $arch (has: $archs)" ;;
      esac
    done
  done < <(find "$app" -type f -print0)
```

- In `--app` mode, add `"$dist/appcast.xml"` to the `rm -f` list.
- `scripts/install-local.sh`: no change (it builds Release, signs with `NUBRIX_SIGN_LOCAL=1`, then runs `verify-bundle.sh`, which now also checks the Sparkle layout).

### 2.8 `.github/workflows/build.yml`

In the job that runs ShellCheck, add a step "Sparkle pins agree" that fails if the Sparkle version in `Package.resolved` differs from `version=` in `scripts/sparkle-tools.sh`:

```bash
resolved="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(next(p["state"]["version"] for p in d["pins"] if p["identity"]=="sparkle"))' Nubrix.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)"
tools="$(sed -n 's/^version="\(.*\)"$/\1/p' scripts/sparkle-tools.sh)"
[ "$resolved" = "$tools" ] || { echo "::error::Package.resolved has Sparkle $resolved but sparkle-tools.sh pins $tools"; exit 1; }
```

Checks for this slice: Release build via `scripts/package-release.sh --build-only` passes `verify-bundle.sh`; `NUBRIX_SIGN_IDENTITY=- scripts/sign-release.sh <copy>` signs 9 Mach-O files and passes; `codesign -d --entitlements - <copy>/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate` prints no entitlements; `scripts/run-tests.sh` still passes.

---

## Slice 3: Sparkle-backed update store, settings and menu; remove the notify-only checker

Commit: "Replace the notify-only update check with opt-in Sparkle updates".

### 3.1 Delete (dead after this slice)

| File | Why |
|---|---|
| `Nubrix/Features/Updates/UpdateClient.swift` | `api.github.com` fetch, `UpdateNoRedirect` |
| `Nubrix/Features/Updates/UpdateParsing.swift` | `UpdateFailure`, `UpdateParsing`, `UpdateVerdict`, `UpdateDecision`, `UpdateSchedule` |
| `Nubrix/Features/Updates/ReleaseVersion.swift` | Only used by the checker; Sparkle compares versions itself |
| `Nubrix/Features/Updates/UpdateInstallKind.swift` | Replaced by `UpdateBuildKind.swift` (its `AppSigningIdentity` moves there and is extended; `UpdateLinks` and the Homebrew/zip instructions go) |
| `NubrixTests/Updates/UpdateClientTests.swift`, `UpdateParsingTests.swift`, `UpdateDecisionTests.swift`, `UpdateScheduleTests.swift`, `ReleaseVersionTests.swift`, `UpdateInstallKindTests.swift`, `UpdateStoreTests.swift` | Test deleted code (`UpdateStoreTests` is replaced by new tests) |
| `isHomebrewInstall` in `NubrixHelper/NubrixHelperProtocol.swift`, `Nubrix/XPCHelperClient/NubrixHelperProtocol.swift`, `NubrixHelper/NubrixHelper.swift`, `Nubrix/XPCHelperClient/XPCHelperClient.swift` | Sparkle updates Homebrew and zip installs the same way; the unsandboxed helper loses a method |

Rewritten: `UpdateStore.swift`, `UpdateViews.swift`, `UpdateDefaults.swift` (new contents in Slice 5). Kept: the source-build idea (Team ID check) inside `UpdateBuildKind`.

### 3.2 `Nubrix/Features/Updates/UpdateBuildKind.swift` (new)

```swift
import Foundation
import Security

struct AppSigningFacts: Equatable, Sendable {
    let satisfiesReleaseRequirement: Bool
    let hasSecureTimestamp: Bool
    let teamIdentifier: String?
}

enum AppSigningIdentity {
    static let releaseRequirement = #"anchor apple generic and identifier "dev.nubrix.app" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "399MAAJ7QT""#

    static func currentFacts() -> AppSigningFacts? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(releaseRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        let satisfies = SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return AppSigningFacts(
            satisfiesReleaseRequirement: satisfies,
            hasSecureTimestamp: dictionary[kSecCodeInfoTimestamp as String] is Date,
            teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }
}

enum UpdateBuildKind: Equatable, Sendable {
    case developerIDRelease
    case sourceBuild
    case debugBuild

    static let releaseBundleIdentifier = "dev.nubrix.app"
    static let releaseTeamIdentifier = "399MAAJ7QT"
    static let feedURL = "https://github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml"

    static func resolve(isDebugBuild: Bool, bundleIdentifier: String?, signing: AppSigningFacts?, info: [String: Any]) -> UpdateBuildKind
    static let current: UpdateBuildKind

    var updatesEnabled: Bool { self == .developerIDRelease }
    var sourceInstructions: String?
}
```

`resolve` rules, in order (fail closed):
1. `isDebugBuild` → `.debugBuild`. `current` passes `true` under `#if DEBUG`.
2. `bundleIdentifier != releaseBundleIdentifier` → `.sourceBuild`.
3. `signing == nil`, or `!satisfiesReleaseRequirement`, or `!hasSecureTimestamp`, or `teamIdentifier != releaseTeamIdentifier` → `.sourceBuild`.
4. `info["SUFeedURL"] as? String != feedURL`, or `SUPublicEDKey` not base64 decoding to 32 bytes, or any of `SUEnableInstallerLauncherService`, `SUVerifyUpdateBeforeExtraction`, `SURequireSignedFeed` not `true` → `.sourceBuild`.
5. Otherwise `.developerIDRelease`.

Why each signal: the requirement (Apple anchor + Developer ID intermediate + Developer ID Application leaf + team OU) rejects ad-hoc and Apple Development builds. The **secure timestamp** rejects the owner's own `install-local.sh` builds: when there is no Apple Development identity that script falls back to a Developer ID Application identity, but signs with `--timestamp=none` (`sign-release.sh` local mode), whereas CI release signing always timestamps. `#if DEBUG` covers Xcode runs and hosted tests. The Info.plist check keeps a misconfigured bundle from starting an updater Sparkle would reject anyway.

`sourceInstructions`: `.sourceBuild` → `"Built from source, so Nubrix does not update itself. In your checkout: git pull && scripts/install-local.sh"`; `.debugBuild` → `"Debug build: updates are off."`; release → `nil`.

`current` is computed once (a `static let`), off the hot path; `SecCodeCheckValidity` on the running code is fast.

### 3.3 `Nubrix/Features/Updates/SparkleUpdater.swift` (new; the only file that imports Sparkle)

```swift
import AppKit
import Combine
import Sparkle

@MainActor
protocol UpdaterControlling: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()
}

extension SPUUpdater: UpdaterControlling {}

struct UpdaterHandle {
    let updater: UpdaterControlling
    let retained: [AnyObject]
}

@MainActor
final class SparkleBridge: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static func make(store: UpdateStore) throws -> UpdaterHandle
}
```

`make`:
1. `let bridge = SparkleBridge(store: store)` (holds `weak var store`).
2. `let driver = SPUStandardUserDriver(hostBundle: .main, delegate: bridge)`.
3. `let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: bridge)`.
4. `try updater.start()` (Swift name of `startUpdater:`). Using `SPUUpdater` directly, not `SPUStandardUpdaterController`, so a start failure becomes a status string instead of a modal alert.
5. `updater.clearFeedURLFromUserDefaults()` (2.4+), so only Info.plist's feed is used.
6. Observe `updater.publisher(for: \.canCheckForUpdates)`, `\.automaticallyChecksForUpdates`, `\.automaticallyDownloadsUpdates` on the main queue → `store?.refresh()`; keep the cancellables in the bridge.
7. Return `UpdaterHandle(updater: updater, retained: [bridge, driver])` (Sparkle holds delegates weakly).

Delegate methods (`nonisolated`, body in `MainActor.assumeIsolated { … }`; Sparkle calls them on the main thread):

| Method | Behaviour |
|---|---|
| `updater(_:mayPerformUpdateCheck:error:)` | `return UpdateBuildKind.current.updatesEnabled` (defence in depth; set a short `NSError` when false) |
| `updater(_:didFinishUpdateCycleFor:error:)` | `store?.cycleFinished(error: error?.localizedDescription)` (refreshes `lastCheck`) |
| `updaterDidNotFindUpdate(_:)` | `store?.noUpdateFound()` |
| `updater(_:didAbortWithError:)` | `store?.cycleFinished(error: …)` |
| `supportsGentleScheduledUpdateReminders` | `true` |
| `standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)` | `false`: Nubrix never pops an update window on its own, not even at login; the reminder (Slice 4) opens it on click |
| `standardUserDriverWillHandleShowingUpdate(_:forUpdate:state:)` | `store?.reminderEvent(.willShow(handledBySparkle: handle, userInitiated: state.userInitiated, version: update.displayVersionString, readyToInstall: state.stage != .notDownloaded))` |
| `standardUserDriverDidReceiveUserAttention(forUpdate:)` | `store?.reminderEvent(.attention)` |
| `standardUserDriverWillFinishUpdateSession()` | `store?.reminderEvent(.sessionFinished)` |

Not implemented: `feedURLString(for:)`, `feedParameters…`, `allowedChannels…`, `updaterShouldPromptForPermissionToCheckForUpdates` (Info.plist already disables the prompt).

### 3.4 `Nubrix/Features/Updates/UpdateStore.swift` (rewrite)

```swift
@MainActor
final class UpdateStore: ObservableObject {
    static let shared = UpdateStore(buildKind: .current, defaults: .standard,
                                    makeUpdater: { try SparkleBridge.make(store: $0) },
                                    activate: { NSApp.activate(ignoringOtherApps: true) })

    enum Status: Equatable { case idle, upToDate, failed(String) }

    @Published private(set) var buildKind: UpdateBuildKind
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyInstalls = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastCheck: Date?
    @Published private(set) var status: Status = .idle
    @Published private(set) var reminder: UpdateReminder?

    static let legacyKeys = ["updateAutoCheck", "updateLastCheck", "updateLatestVersion", "updateSkippedVersion"]

    func start()
    func stop()
    func refresh()
    func setAutomaticallyChecks(_ on: Bool)
    func setAutomaticallyInstalls(_ on: Bool)
    func checkNow()
    func cycleFinished(error: String?)
    func noUpdateFound()
    func reminderEvent(_ event: UpdateReminderEvent)
}
```

Semantics:
- `start()`: if `!buildKind.updatesEnabled` → `migrateLegacyDefaults(updater: nil)` and return (no `SPUUpdater` is ever created). Otherwise create the handle once (`try makeUpdater(self)`; on error `status = .failed(error.localizedDescription)` and return), `migrateLegacyDefaults(updater:)`, `refresh()`. `AppDelegate` already skips `start()` under XCTest; tests call `start()` with a fake factory.
- `refresh()`: copy `automaticallyChecksForUpdates`, `automaticallyDownloadsUpdates`, `canCheckForUpdates`, `lastUpdateCheckDate` from the updater into the published properties.
- `setAutomaticallyChecks(false)`: first `automaticallyDownloadsUpdates = false` (while it is still allowed), then `automaticallyChecksForUpdates = false`, so turning checks back on later does not silently re-enable automatic installs. `setAutomaticallyChecks(true)`: only `automaticallyChecksForUpdates = true` (Sparkle resets its cycle itself; with no previous check it checks shortly after).
- `setAutomaticallyInstalls(_:)`: no-op unless `automaticallyChecksForUpdates` is true (mirrors Sparkle, which ignores the setter then).
- `checkNow()`: requires `canCheckForUpdates`; `activate()` (the app is `LSUIElement`, so the alert would otherwise open behind other apps), then `updater.checkForUpdates()`. Also used to bring a pending update back (Sparkle resumes the session and shows it in focus).
- `noUpdateFound()` → `status = .upToDate`; `cycleFinished(error:)` → `.failed(msg)` or keep, then `refresh()`.
- `migrateLegacyDefaults(updater:)`: runs only if any of `legacyKeys` exists. If `updateAutoCheck` is `true`, an updater exists, and `defaults.object(forKey: "SUEnableAutomaticChecks") == nil`, set `automaticallyChecksForUpdates = true` (the user already opted into a daily check; automatic install stays off). Then remove all four keys. Non-release builds just remove them.

`stop()` drops the handle (no Sparkle cleanup API is needed).

### 3.5 `Nubrix/Features/Updates/UpdateViews.swift` (rewrite)

`UpdatesSettingsSection` (stays in `About`, after "Version info"):

- Header "Updates".
- `.developerIDRelease`:
  - `Toggle("Check for updates automatically")` → `setAutomaticallyChecks`.
  - `Toggle("Install updates automatically")` → `setAutomaticallyInstalls`, `.disabled(!store.automaticallyChecks)`; caption "Downloads in the background and installs when you quit Nubrix."
  - Row: "Version \(short) (\(build))" and "Last checked \(relative)" or "Never checked"; trailing `Button("Check Now")` `.disabled(!store.canCheckForUpdates)`.
  - Status line: `.upToDate` "Nubrix is up to date"; `.failed(m)` "Couldn't check: \(m)".
  - If `reminder != nil`: "Nubrix \(version) is available" (or "is ready to install") with `Button("Show Update…")` → `checkNow()`.
  - Footer: "Off until you turn it on. Nubrix then asks github.com/murathanbakti/nubrix for a signed update feed once a day. An update is installed only if its EdDSA signature and Apple Developer ID signature check out. Installed with Homebrew? brew upgrade --cask nubrix keeps working too."
- `.sourceBuild` / `.debugBuild`: the `sourceInstructions` text; for `.sourceBuild` the command `git pull && scripts/install-local.sh` in monospaced selectable text with a Copy button. No toggles, no Check Now.
- Hook-kit rows (Slice 5) go at the end of this section for every build kind.

`UpdateMenuItems` (already inserted above Settings in `NubrixApp.swift`):
- Release only: if `reminder` → `Button(reminder.readyToInstall ? "Restart to Update Nubrix \(v)…" : "Update to Nubrix \(v)…") { store.checkNow() }`; always `Button("Check for Updates…") { store.checkNow() }.disabled(!store.canCheckForUpdates)`.
- Slice 5 adds the hooks item.
- `Divider()` only if at least one item was shown.
- Source and Debug builds show no update items (Settings explains why).

`NubrixApp.swift`: no change beyond what already exists (`UpdateMenuItems()`, `UpdateStore.shared.start()`, `stop()`).

### 3.6 Tests (Slice 3)

All in `NubrixTests/Updates/`, no Sparkle types, no network.

- `UpdateBuildKindTests.swift`: debug flag wins; wrong bundle id (`dev.nubrix.app.debug`, nil); signing nil; requirement false; **no secure timestamp → source** (the install-local Developer ID case); wrong team; wrong/HTTP feed URL; key missing, wrong length, not base64; each security key false or missing; all good → release. `sourceInstructions` per kind.
- `UpdateInfoPlistTests.swift`: reads the **host app's** `Bundle.main.infoDictionary` (the Debug host merges the same `Nubrix/Info.plist`): exact `SUFeedURL`, `SUPublicEDKey` decodes to 32 bytes, the six booleans, and absence of `SUEnableDownloaderService`, `SUAllowsAutomaticUpdates`, `SUScheduledCheckInterval`.
- `UpdateStoreTests.swift` with `FakeUpdater: UpdaterControlling` that mimics Sparkle (setting downloads is ignored while checks are off; downloads read false while checks are off):
  - `.debugBuild`/`.sourceBuild` → `start()` never calls the factory; legacy keys removed.
  - defaults: after `start()` both toggles off, no `checkForUpdates()` call.
  - install requires checks; turning checks off clears downloads first (the fake records order) and turning checks on again leaves installs off.
  - `checkNow()` calls `activate` then `checkForUpdates`, and does nothing when `canCheckForUpdates` is false.
  - factory throws → `.failed`, no crash.
  - migration with an in-memory `UserDefaults(suiteName:)`: `updateAutoCheck = true` → checks on, installs off, keys gone; `false`/absent → off, keys gone; existing `SUEnableAutomaticChecks = false` wins; no legacy keys → nothing touched.

---

## Slice 4: Gentle reminders and the notch inbox

Commit: "Show pending updates gently in the menu bar and the notch inbox".

### `Nubrix/Features/Updates/UpdateReminder.swift` (new, pure)

```swift
struct UpdateReminder: Equatable, Sendable {
    let version: String
    let readyToInstall: Bool
}

enum UpdateReminderEvent: Equatable, Sendable {
    case willShow(handledBySparkle: Bool, userInitiated: Bool, version: String, readyToInstall: Bool)
    case attention
    case sessionFinished
}

enum UpdateReminderLogic {
    static func reduce(_ current: UpdateReminder?, _ event: UpdateReminderEvent) -> UpdateReminder?
}
```

Rules: `.willShow(handledBySparkle: false, userInitiated: false, …)` → `UpdateReminder(version, readyToInstall)`; any `.willShow` with `handledBySparkle == true` or `userInitiated == true` → unchanged; `.attention`, `.sessionFinished` → `nil`.

`UpdateStore.reminderEvent(_:)` applies `reduce`; when it goes nil → non-nil call `NubrixInbox.shared.appNotice(key: "update", title: "Nubrix \(v) is available", message: "Open Check for Updates in the menu bar, or Settings, About.")`; when it goes to nil call `NubrixInbox.shared.clearAppNotice(key: "update")`.

Where the indicator appears: (1) the menu bar menu item from Slice 3; (2) the notch inbox, which also covers users who hid the menu bar icon (`menubarIcon` off); (3) Settings, About, Updates. No Dock icon, no system notification, no window until the user clicks.

### Inbox changes

- `Nubrix/Features/Inbox/InboxModel.swift`: `enum InboxSource` gains `case nubrix`. `InboxLedger` gains:
  - `mutating func recordApp(key: String, title: String, message: String, date: Date = Date()) -> Bool`: removes entries with `source == .nubrix && key == key`, inserts a `.notice` entry with that key.
  - `mutating func clearApp(key: String) -> Bool`.
- `Nubrix/Features/Inbox/NubrixInbox.swift`: `targetTab` `.nubrix → .home`; `title` "Nubrix"; `isEnabled` `true`; `sources(for: .home)` → `[.nubrix]`; `appNotice(key:title:message:)` and `clearAppNotice(key:)` wrappers.

Tests: `NubrixTests/Updates/UpdateReminderTests.swift` (every transition above, including "user-initiated check never creates a reminder" and "ready-to-install label"); add `InboxLedger` cases for `recordApp` replace-by-key and `clearApp` to the existing inbox tests (or a new `NubrixTests/Updates/InboxAppNoticeTests.swift`); `UpdateStoreTests`: reminder appears and clears via the fake events.

---

## Slice 5: Post-update hook reminder

Commit: "Remind to refresh the sealed hook copies when they differ from the app's".

Sparkle (and `brew upgrade`, and the install script) replace the bundle but cannot refresh `~/.config/nubrix/bin` (the sandbox only reads it, by design). The scripts have no version, so compare bytes.

### `Nubrix/Features/Updates/HookKitStatus.swift` (new)

```swift
enum HookKitState: Equatable, Sendable {
    case notInstalled
    case current
    case stale([String])
    case unknown
}

enum HookKit {
    static let files: [(installed: String, bundled: String)] = [
        ("nubrix-hook", "claude-plugin/scripts/nubrix-hook"),
        ("nubrix-permission", "claude-plugin/scripts/nubrix-permission"),
        ("nubrix-statusline", "claude-plugin/scripts/nubrix-statusline"),
        ("notchctl", "cli/notchctl"),
    ]
    static let maxFileSize = 1_048_576

    static func evaluate(installed: [String: Data], bundled: [String: Data]) -> HookKitState
    static func shouldNotify(state: HookKitState, lastNotifiedBuild: String?, currentBuild: String?, buildKind: UpdateBuildKind) -> Bool
    static func installCommand(bundlePath: String) -> String
}

@MainActor
final class HookKitStore: ObservableObject {
    static let shared: HookKitStore
    @Published private(set) var state: HookKitState = .unknown
    func refresh() async
    func launchCheck() async
}
```

- `evaluate`: any bundled file missing → `.unknown` (never nag on a broken bundle); no installed file at all → `.notInstalled`; names whose installed bytes differ or are missing → `.stale(names)`; else `.current`.
- Reading: installed from `AgentEventServer.configDirectory/bin/<name>` (real home via `getpwuid`, already used); bundled from `Bundle.main.resourceURL/nubrix-hooks/<rel>`. Skip symlinks and files over `maxFileSize`; read off the main actor (`Task.detached(priority: .utility)`).
- `shouldNotify`: `state` is `.stale`, `buildKind != .debugBuild`, and `lastNotifiedBuild != currentBuild` (`CFBundleVersion`). So the inbox notice appears once per installed version, on its first launch, whatever updated the app.
- `installCommand`: `bash "<bundlePath>/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh"` with the path quoted (uses the real bundle path, not a hard-coded `/Applications`).
- `launchCheck()` (called from `applicationDidFinishLaunching` right after `UpdateStore.shared.start()`, inside `Task { await … }`): `refresh()`, then if `shouldNotify` → `NubrixInbox.shared.appNotice(key: "hooks", title: "Refresh your Claude Code hooks", message: "This Nubrix version has newer hook scripts. Settings, About shows the command.")` and store `Defaults[.hookReminderNotifiedBuild] = currentBuild`. If the state is `.current` → `clearAppNotice(key: "hooks")`.
- Settings `onAppear` calls `refresh()`.

### `Nubrix/Features/Updates/UpdateDefaults.swift` (rewritten)

```swift
extension Defaults.Keys {
    static let hookReminderNotifiedBuild = Key<String?>("hookReminderNotifiedBuild", default: nil)
}
```

(Do not reuse `LastVersionRun`; `isNewVersion()` mutates it.)

### UI

- Settings, About, Updates (all build kinds): if `.stale(names)` → "Your installed Claude Code hook scripts are older than this Nubrix (\(names.joined(", ")))." + the command in monospaced selectable text + `Button("Copy")` + `Button("Check Again")`. `.notInstalled`, `.current`, `.unknown` → nothing.
- Menu: if `.stale` → `Button("Refresh Claude Code Hooks…") { SettingsNavigation.shared.open("About") }`.

Tests: `NubrixTests/Updates/HookKitStatusTests.swift`: not installed; all equal → current; one differs → stale([that]); one missing among installed → stale; bundled missing → unknown; `shouldNotify` matrix (same build → no; new build + stale → yes; debug → no; current → no); `installCommand` quotes a path with spaces.

---

## Slice 6: Signed appcast in the release workflow

Commit: "Generate and upload a signed appcast with each release".

### `scripts/make-appcast.sh` (new)

```
usage: scripts/make-appcast.sh --tools DIR --tag vX.Y.Z --zip dist/Nubrix-X.Y.Z.zip --out dist/appcast.xml
```

Key source: `SPARKLE_ED_PRIVATE_KEY` env var (CI) → tools get `--ed-key-file -` with the key on stdin; unset (owner's Mac) → `--account nubrix` (keychain).

```bash
#!/bin/bash
set -euo pipefail

repo_url="https://github.com/murathanbakti/nubrix"
feed_url="$repo_url/releases/latest/download/appcast.xml"

usage() { echo "usage: $0 --tools DIR --tag vX.Y.Z --zip PATH --out PATH" >&2; exit 2; }
fail() { echo "make-appcast: $*" >&2; exit 1; }

tools="" tag="" zip="" out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --tools | --tag | --zip | --out)
      [ $# -ge 2 ] && [ -n "$2" ] || usage
      case "$1" in
        --tools) tools="$2" ;;
        --tag) tag="$2" ;;
        --zip) zip="$2" ;;
        --out) out="$2" ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
[ -n "$tools" ] && [ -n "$tag" ] && [ -n "$zip" ] && [ -n "$out" ] || usage
[[ "$tag" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] || fail "tag must be vX.Y.Z"
version="${BASH_REMATCH[1]}"
[ -f "$zip" ] && [ "$(basename "$zip")" = "Nubrix-$version.zip" ] || fail "expected $zip to be Nubrix-$version.zip"
for t in generate_appcast sign_update; do [ -x "$tools/$t" ] || fail "missing $tools/$t"; done

with_key() {
  if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$@" --ed-key-file -
  else
    "$@" --account nubrix
  fi
}

work="$(mktemp -d "${TMPDIR:-/tmp}/nubrix-appcast.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir "$work/archives" "$work/app"
cp "$zip" "$work/archives/"
ditto -x -k "$zip" "$work/app"
[ "$(ls "$work/app")" = "Nubrix.app" ] || fail "the zip must hold only Nubrix.app"
plist="$work/app/Nubrix.app/Contents/Info.plist"
pl() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist"; }
[ "$(pl CFBundleShortVersionString)" = "$version" ] || fail "CFBundleShortVersionString is not $version"
build="$(pl CFBundleVersion)"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || fail "CFBundleVersion '$build' must be a positive integer"
[ "$(pl LSMinimumSystemVersion)" = "14.0" ] || fail "LSMinimumSystemVersion is not 14.0"
[ "$(pl SUFeedURL)" = "$feed_url" ] || fail "SUFeedURL is not $feed_url"

code="$(curl -sS --proto '=https' --tlsv1.2 -L --max-redirs 5 -o "$work/previous.xml" -w '%{http_code}' "$feed_url" || true)"
case "$code" in
  200)
    prev="$(xmllint --xpath 'string(//*[local-name()="item"][1]/*[local-name()="version"])' "$work/previous.xml")"
    [[ "$prev" =~ ^[0-9]+$ ]] || fail "cannot read sparkle:version from the published appcast"
    [ "$build" -gt "$prev" ] || fail "CFBundleVersion $build is not greater than the published $prev; bump CURRENT_PROJECT_VERSION"
    ;;
  404) echo "No published appcast yet; writing the first one." ;;
  *) fail "unexpected HTTP $code for $feed_url" ;;
esac

(cd "$work" && with_key "$tools/generate_appcast" \
  --download-url-prefix "$repo_url/releases/download/$tag/" \
  --link "$repo_url/releases/tag/$tag" \
  --maximum-deltas 0 --maximum-versions 1 \
  -o "$work/appcast.xml" "$work/archives")

feed="$work/appcast.xml"
x() { xmllint --xpath "$1" "$feed"; }
item='//*[local-name()="item"]'
[ "$(x "count($item)")" = 1 ] || fail "expected exactly one item"
[ "$(x "string($item/*[local-name()=\"version\"])")" = "$build" ] || fail "sparkle:version is not $build"
[ "$(x "string($item/*[local-name()=\"shortVersionString\"])")" = "$version" ] || fail "shortVersionString is not $version"
[ "$(x "string($item/*[local-name()=\"minimumSystemVersion\"])")" = "14.0" ] || fail "minimumSystemVersion is not 14.0"
[ "$(x "string($item/*[local-name()=\"enclosure\"]/@url)")" = "$repo_url/releases/download/$tag/Nubrix-$version.zip" ] || fail "enclosure URL is wrong"
[ "$(x "string($item/*[local-name()=\"enclosure\"]/@length)")" = "$(stat -f %z "$zip")" ] || fail "enclosure length is wrong"
sig="$(x "string($item/*[local-name()=\"enclosure\"]/@*[local-name()=\"edSignature\"])")"
[ -n "$sig" ] || fail "no EdDSA signature: the private key does not match SUPublicEDKey"
[ "$(x "count($item/*[local-name()=\"deltas\" or local-name()=\"releaseNotesLink\" or local-name()=\"description\"])")" = 0 ] || fail "unexpected deltas or release notes"
grep -qx '<!-- sparkle-signatures:' "$feed" || fail "the appcast is not signed"
with_key "$tools/sign_update" --verify "$feed" >/dev/null || fail "appcast signature does not verify"
with_key "$tools/sign_update" --verify "$zip" "$sig" >/dev/null || fail "archive signature does not verify"
cp "$feed" "$out"
echo "Appcast: $out (sparkle:version $build, $version)"
```

Note on `with_key`: the key flag is appended after the other arguments; ArgumentParser accepts options in any position. For `sign_update --verify <file> <sig>` the trailing `--ed-key-file -` is still parsed as an option. Run once locally (Owner step C) to confirm.

### `.github/workflows/release.yml`

1. `build` job, step "Check tag against MARKETING_VERSION": also read `CURRENT_PROJECT_VERSION` and require `^[1-9][0-9]*$` (the monotonic check against the published feed happens in `make-appcast.sh`).
2. `release` job, step "Choose signing mode": add `SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}` to its `env`; in the ad-hoc branch add `[[ -z "$SPARKLE_ED_PRIVATE_KEY" ]] || present+=("secret SPARKLE_ED_PRIVATE_KEY")`; in the Developer ID branch add `[[ -n "$SPARKLE_ED_PRIVATE_KEY" ]] || missing+=("secret SPARKLE_ED_PRIVATE_KEY")`. This fails before the 45-minute notarization, not after.
3. New step **after "Verify release zip"** (which runs after "Remove signing keychain and notary key", so the Developer ID keychain and the `.p8` are already gone) and **before "Create draft release"**:

```yaml
      - name: Generate signed appcast
        if: env.SIGNING_MODE == 'developer-id'
        env:
          SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
        run: |
          tools="$(scripts/sparkle-tools.sh "$RUNNER_TEMP/sparkle-tools")"
          scripts/make-appcast.sh --tools "$tools" --tag "$TAG" --zip "dist/Nubrix-$VERSION.zip" --out dist/appcast.xml
```

4. "Create draft release":

```bash
          assets=(dist/Nubrix-*.zip dist/Nubrix-*.zip.sha256)
          if [[ "$SIGNING_MODE" == "developer-id" ]]; then
            [[ -f dist/appcast.xml ]] || { echo "::error::dist/appcast.xml is missing"; exit 1; }
            assets+=(dist/appcast.xml)
          fi
          ...
            gh release upload "$TAG" "${assets[@]}" --clobber
          ...
            gh release create "$TAG" "${assets[@]}" \
              --draft --verify-tag --title "Nubrix $VERSION" --notes "$signing_note" --generate-notes
```

Ad-hoc (fork) releases get no appcast: their builds resolve to `.sourceBuild` anyway.

5. "Summary": add "Appcast: `appcast.xml` attached; Sparkle sees it at `releases/latest/download/appcast.xml` once you publish this draft." and the `sparkle:version`.

The `GH_TOKEN` stays only in the "Create draft release" step's env, so the Sparkle tool never runs with the write token or the Apple secrets in its environment.

Release flow afterwards: tag → build → sign/notarize → appcast → draft with zip, `.sha256`, `appcast.xml` → owner publishes → `releases/latest` (drafts and prereleases excluded) now serves the new `appcast.xml` → enclosure URL `…/releases/download/vX.Y.Z/Nubrix-X.Y.Z.zip` resolves through the same redirect chain.

---

## Slice 7: Homebrew, docs and licenses

Commit: "Document Sparkle updates, its network use and its license".

### Homebrew: leave `auto_updates` out (recommended)

- With `auto_updates true`, plain `brew upgrade` skips the cask; only `--greedy`, `--greedy-auto-updates` or `HOMEBREW_UPGRADE_GREEDY` include it (manpage). Most users never turn on Sparkle (it is off by default), so they would silently stop getting upgrades from brew.
- The Cask Cookbook says to use `auto_updates true` when the app downloads and installs updates itself. That is a rule for the official homebrew-cask repository; `murathanbakti/homebrew-tap` is a personal tap.
- Cost of leaving it out: for users who did turn Sparkle on, brew's recorded version lags. A later `brew upgrade` then downloads the same, already installed version once more (and quits Nubrix through `uninstall quit:`). That is harmless, and it uses the same notarized zip.
- `packaging/homebrew/nubrix.rb.template`: no `auto_updates`; extend `caveats`:
  ```
  Nubrix can also update itself if you turn that on in Settings, About, Updates.
  brew upgrade --cask nubrix keeps working either way.
  ```
  Keep the hook line ("Run it again after every upgrade…").

### Docs

- `README.md`:
  - Privacy, "Local only": replace the "no auto-updater …" clause with "optional automatic updates through Sparkle, off until you turn them on"; in the network sentence replace "the release check above" with "the signed update feed on github.com when you turn on update checks or press Check Now".
  - "What's new": nothing (Unreleased goes in CHANGELOG).
  - "Updating": rewrite. Settings, About, Updates: "Check for updates automatically", "Install updates automatically" (needs the first), Check Now, also in the menu bar. Only Developer ID releases (Homebrew, the install script, the release zip) update themselves; source and Debug builds show `git pull && scripts/install-local.sh`. 0.1.2 and older have no Sparkle, so update those once by hand (`brew upgrade --cask nubrix` or the install script). After any update Nubrix tells you if the sealed hook copies are out of date and shows the `install-hooks.sh` command.
- `docs/nubrix/PRIVACY-AND-SECURITY.md`:
  - "Local only": same wording change.
  - "Network use": replace the `api.github.com/…/releases/latest` bullet with: `github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml` (GitHub redirects to `release-assets.githubusercontent.com`), only when automatic checks are on (once a day) or you press Check Now; off by default. Sparkle sends a plain GET with `User-Agent: Nubrix/<version> Sparkle/<version>`, no GitHub token, no system profile (`SUEnableSystemProfiling` is off). The feed must carry a valid EdDSA signature (`SURequireSignedFeed`). When you install an update (or with "Install updates automatically"), Sparkle downloads `Nubrix-X.Y.Z.zip` from the same release, checks its EdDSA signature before unpacking (`SUVerifyUpdateBeforeExtraction`) and checks that the new app is signed with the same Developer ID. Stored on your Mac (app container defaults): `SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SULastCheckTime` and Sparkle's skipped-version state.
  - "Sandbox and helper split": the app gains one mach-lookup temporary exception (`dev.nubrix.app-spks`, `-spki`) so it can talk to Sparkle's installer. The installer (`Installer.xpc` → `Autoupdate`, `Updater.app`) runs outside the sandbox only to replace the bundle. The Downloader service is removed from the bundle. NubrixHelper lost `isHomebrewInstall`.
  - "Signing": release bundles now contain 9 Mach-O files; Sparkle's are re-signed with the Developer ID, without entitlements.
- `docs/nubrix/SUPPLY-CHAIN.md`: rename the page title to "Supply chain" (keep the mediaremote-adapter section) and add a "Sparkle" section: version 2.10.1, SwiftPM `exactVersion`, revision `ab7d712…`, binary checksum `4c2e48a3…` enforced by SwiftPM; embedded Mach-O inventory (4 files) and the build-time removal of `Downloader.xpc`; release signing inside-out without entitlements (Autoupdate ships with `com.apple.application-identifier`, which is dropped); CLI tools from `Sparkle-2.10.1.tar.xz` pinned by SHA-256 `1a856d2a…` in `scripts/sparkle-tools.sh`, run in the release job after the Apple secrets are deleted, with only `SPARKLE_ED_PRIVATE_KEY` in their environment; how to upgrade (change both pins, CI step "Sparkle pins agree", read the release notes, rerun `verify-bundle.sh`).
- `THIRD_PARTY_LICENSES`: new block before or after the MIT block:
  ```
  -----------------------------------------------------------------------------
                          Sparkle
          applies to:
          - Sparkle 2.10.1 (Sparkle.framework, embedded), https://sparkle-project.org
  -----------------------------------------------------------------------------
  ```
  followed by the **verbatim** 134-line `LICENSE` from tag 2.10.1 (`https://raw.githubusercontent.com/sparkle-project/Sparkle/2.10.1/LICENSE`, also `./LICENSE` in the pinned tarball): Sparkle's MIT text and its external licenses (bsdiff/bspatch BSD, sais-lite MIT, ed25519 zlib, `SUSignatureVerifier.m` BSD). Copy it from the file; do not retype it. `NOTICE` needs no change (it points to `THIRD_PARTY_LICENSES`).
- `docs/nubrix/INSTALL.md`: under "Next steps", a short "Updates" paragraph (opt-in, where to turn it on, Homebrew keeps working, source builds update with `git pull && scripts/install-local.sh`).
- `docs/nubrix/ROADMAP.md`: Phase 5 "Done locally": replace "Auto-updater removed…" with "Sparkle 2 auto-updates (opt-in, signed feed, Developer ID builds only), replacing the notify-only check". Replace the "Update check (notify only)…" bullet under "Published" once released.
- `CHANGELOG.md`, new `## [Unreleased]` above 0.1.2:
  - Added: opt-in automatic updates with Sparkle 2.10.1 (check automatically, install automatically, Check Now, last check time), gentle reminders in the menu bar and the notch inbox; a reminder when the installed hook scripts differ from the app's.
  - Changed: Sparkle replaces the notify-only check; source and Debug builds never update themselves.
  - Removed: the `api.github.com` release check and the helper's Homebrew probe.
  - Security: signed appcast (`SURequireSignedFeed`), EdDSA verification before extraction, Developer ID match; one new mach-lookup temporary exception; four new Mach-O files (Sparkle), Downloader service removed.
- `CONTRIBUTING.md`, "Releases (maintainer)": step 1 also bumps `CURRENT_PROJECT_VERSION` (app **and** helper) on every release; step 3 mentions `appcast.xml` and that the release job runs exactly one pinned third-party tool (Sparkle's), after the Apple secrets are deleted (replace "It never compiles or runs third-party code"); step 4: publishing the draft is what ships the update to Sparkle users. "Signing and notarization": add Sparkle to the inside-out order (`Installer.xpc`, `Autoupdate`, `Updater.app`, `Sparkle.framework`, no entitlements), the `SPARKLE_ED_PRIVATE_KEY` row in the secrets table, and `scripts/setup-sparkle-key.sh`. Replace "There is no auto-updater…".
- `docs/nubrix/TROUBLESHOOTING.md`: "Check for Updates is missing or greyed out" (source/Debug build, or start failed: Settings shows the reason) and "An update failed to install" (quit and reopen; reinstall with brew or the script).
- `docs/nubrix/plans/update-mechanism.md`: status line → "Superseded by sparkle-auto-update.md".

---

## Slice 8 (optional): bash test for `verify-bundle.sh`

Commit: "Test verify-bundle's allowlist and update keys".

`scripts/test-verify-bundle.sh`, run in `build.yml` (macOS job) after ShellCheck:
1. Build a minimal bundle in `mktemp -d`: copy `/usr/bin/true` (universal Mach-O) to each of the 9 expected paths; give every bundle (`Nubrix.app`, `NubrixHelper.xpc`, the three frameworks with `Versions/A|B` + `Current` symlinks + `Resources/Info.plist`, `Updater.app`, `Installer.xpc`) a minimal `Info.plist`; write the app's `Info.plist` with all `SU*` keys and a dummy 32-byte base64 key; create the five hook kit files executable.
2. Sign ad-hoc inside-out with `--options runtime`; the app with an entitlements plist containing `disable-library-validation` and the two mach-lookup names.
3. Assert pass; then for each mutation assert failure with the expected message: extra Mach-O in `Resources`; `Downloader.xpc` present; `Installer.xpc` missing; `SUEnableAutomaticChecks` true; `SUEnableDownloaderService` set; `SUFeedURL` http; mach-lookup names for another bundle id.

If constructing signable fake frameworks proves brittle, keep cases that fail before `codesign --verify` (allowlist and plist checks run first) and drop the "pass" case.

---

## Full test list

| Test | Slice | What |
|---|---|---|
| `NubrixTests/Updates/UpdateBuildKindTests.swift` | 3 | resolve matrix incl. no-timestamp Developer ID → source |
| `NubrixTests/Updates/UpdateInfoPlistTests.swift` | 3 | shipped `SU*` keys exact, absent keys absent |
| `NubrixTests/Updates/UpdateStoreTests.swift` | 3, 4 | defaults off, install-needs-check, off order, Check Now gating + activation, factory failure, no updater outside release, legacy migration, reminder → inbox |
| `NubrixTests/Updates/UpdateReminderTests.swift` | 4 | reducer transitions |
| `NubrixTests/Updates/InboxAppNoticeTests.swift` | 4 | `recordApp` / `clearApp`, `.nubrix` maps to `.home` |
| `NubrixTests/Updates/HookKitStatusTests.swift` | 5 | evaluate, shouldNotify, command quoting |
| `scripts/test-verify-bundle.sh` | 8 | allowlist + plist + entitlement checks |
| In-pipeline assertions in `make-appcast.sh` | 6 | one item, versions, min OS, URL, length, EdDSA on enclosure, signed feed, both `sign_update --verify` |
| CI "Sparkle pins agree" | 2 | `Package.resolved` = `sparkle-tools.sh` |
| `scripts/run-tests.sh` | all | the hosted suite stays green |

Not unit-testable (on-device, Owner step D): Sparkle's actual install, the sandboxed installer connection, the redirect chain from the app, gentle reminder timing.

---

## Owner steps

**A. Create the key (after Slice 1 is merged, before Slice 2).** In your own terminal (not through Claude):

```sh
cd ~/Developer/nubrix
scripts/setup-sparkle-key.sh --backup
```

It creates (or reuses) the EdDSA key in your login keychain under account `nubrix`, stores the private key as `SPARKLE_ED_PRIVATE_KEY` in the `release` environment without printing it, writes a backup to `~/.nubrix-signing/sparkle-ed25519.key`, and prints the public key. Paste only the public key into the chat (or into `Nubrix/Info.plist` as `SUPublicEDKey` yourself). Copy `~/.nubrix-signing` to your password manager or encrypted disk: losing this key means installed copies can never auto-update again (see Open risks).

**B. Merge Slices 2–7** (the key is in `Nubrix/Info.plist`).

**C. Dry run before tagging (optional, recommended).** `scripts/package-release.sh` with your Developer ID locally, then:

```sh
tools="$(scripts/sparkle-tools.sh "$(mktemp -d)/t")"
scripts/make-appcast.sh --tools "$tools" --tag vX.Y.Z --zip dist/Nubrix-X.Y.Z.zip --out /tmp/appcast.xml
```

(no env var → it signs from your keychain). It fails if the key does not match `SUPublicEDKey`.

**D. Cut the first Sparkle release** (e.g. 0.2.0): bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (to at least 4) in app and helper, tag, let the workflow draft it, check that the draft has `appcast.xml`, publish, update the tap cask. Then `curl -sL https://github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml | tail -5` shows the signature block.

**E. Prove an update end to end with the second Sparkle release** (0.2.1): on a test Mac with 0.2.0 from the zip or brew, turn on "Check for updates automatically" (or press Check Now), install 0.2.1 from the alert, confirm it relaunches as 0.2.1, permissions (Accessibility, Full Disk Access, Camera, Calendar) still granted, the hooks reminder appears if the scripts changed, and `codesign -dv` shows the Developer ID. Also check with `nettop`/Little Snitch that a fresh 0.2.0 makes no request before you opt in.

---

## Open risks

1. **Third-party code in the release job.** The job now runs Sparkle's `generate_appcast` and `sign_update` with the EdDSA private key. Mitigations in the spec: SHA-256 pin, step runs after the Developer ID keychain and notary key are deleted, `GH_TOKEN` not in its env. Stronger option: move appcast generation to a separate job (environment `release`, `contents: read`, only `SPARKLE_ED_PRIVATE_KEY`) that passes `appcast.xml` as an artifact to a final job that creates the draft. That is a later hardening; the owner chose the single job.
2. **Losing the EdDSA key ends auto-updates for installed copies.** With `SUVerifyUpdateBeforeExtraction`, a key change is only accepted through a Developer ID signed **DMG**, and Nubrix ships zips. Keep the keychain item and the `--backup` copy. Never change the Developer ID and the EdDSA key in the same release.
3. **`SUSignedFeedFailureExpirationInterval`** stays at its 20-day default: if the feed signature fails for 20 days, Sparkle falls back to showing updates without feed metadata (archives are still EdDSA-checked before extraction). Setting it to 0 removes that recovery path. Revisit if the threat model changes.
4. **`CFBundleVersion` must grow every release.** It was 3 for 0.1.2. `make-appcast.sh` fails the release if it does not exceed the published feed's `sparkle:version`.
5. **`releases/latest` decides what Sparkle sees.** Publishing an older backport release after a newer one may make it "Latest"; Sparkle won't downgrade, but users would not see the newer one. Mark the right release as Latest.
6. **Users on 0.1.2 and older have no Sparkle.** They update once by hand; 0.1.2's notify-only check (still hitting `api.github.com`) tells them.
7. **`ENABLE_USER_SCRIPT_SANDBOXING = NO` on the app target** for the strip phase. Alternative if this is unwanted: keep `Downloader.xpc`, sign it with `--preserve-metadata=entitlements`, and add it to the allowlist (10 Mach-O files).
8. **Autoupdate's `com.apple.application-identifier` entitlement** (present in 2.10.1's build) is stripped by our signing. Check the notary log of the first Sparkle release for warnings on Sparkle's files, and recheck this when bumping Sparkle.
9. **Hosted tests import `Nubrix`, which now links Sparkle.** If the test target cannot find the Sparkle module, add `$(BUILT_PRODUCTS_DIR)/PackageFrameworks` to the test target's `FRAMEWORK_SEARCH_PATHS` (Lottie already works the same way, so this is unlikely).
10. **Homebrew drift.** Without `auto_updates`, brew may re-download an already installed version after a Sparkle update and quit Nubrix while doing it. Accepted for plain `brew upgrade` to keep working.
11. **Files outside the container.** Sparkle's installer may leave caches under `~/Library/Caches/dev.nubrix.app/org.sparkle-project.Sparkle`. Check after Owner step E and add confirmed paths to the cask's `zap`.
12. **Installer authorization.** If `/Applications/Nubrix.app` is not writable by the user (e.g. copied by another admin), Sparkle asks for an administrator password; "Install updates automatically" then shows a prompt instead of installing silently.
13. **Gentle reminders return `false` for immediate focus too**, so Sparkle never opens a window on its own, even right after launch. If users miss updates, switch `standardUserDriverShouldHandleShowingScheduledUpdate` to `return immediateFocus` (Sparkle's documented default pattern).
14. **Legacy opt-in carry-over.** Users who turned on the 0.1.2 daily check get Sparkle's automatic checks (not installs) turned on. Drop the migration if that consent should be asked again.
15. **First end-to-end proof needs two Sparkle releases** (0.2.0 → 0.2.1). Keep 0.2.1 small.

---

## Sources

Sparkle (all at tag 2.10.1 unless noted):
- Releases and assets (2.10.1 date, tarball and SwiftPM zip digests): https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1
- `Package.swift` (product `Sparkle`, binary target URL and checksum): https://github.com/sparkle-project/Sparkle/blob/2.10.1/Package.swift
- Basic setup, key backup, key rotation, library validation note: https://sparkle-project.org/documentation/
- Sandboxing (Installer service, Downloader only without `network.client`, mach-lookup exception, manual re-sign commands without `--deep`, stripping XPC services): https://sparkle-project.org/documentation/sandboxing/
- Info.plist settings (`SUEnableAutomaticChecks`, `SUAutomaticallyUpdate`, `SUAllowsAutomaticUpdates`, `SUVerifyUpdateBeforeExtraction` ≥ 2.7.3, `SURequireSignedFeed` ≥ 2.9 requiring it, `SUSignedFeedFailureExpirationInterval`, `SUShowReleaseNotes`, `SUEnableSystemProfiling`, sandbox keys): https://sparkle-project.org/documentation/customization/
- Publishing (archives, `sign_update`, signing the appcast for `SURequireSignedFeed`, `sparkle:version` vs `shortVersionString`, `minimumSystemVersion`): https://sparkle-project.org/documentation/publishing/
- Gentle reminders (API and background-app guidance): https://sparkle-project.org/documentation/gentle-reminders/
- Settings UI (properties backed by user defaults, set only on user change): https://sparkle-project.org/documentation/preferences-ui/
- Programmatic setup (`SPUUpdater` vs `SPUStandardUpdaterController`, `canCheckForUpdates` publisher): https://sparkle-project.org/documentation/programmatic-setup/
- Source checked: `Sparkle/SPUUpdater.m` (`startUpdateCycle`, `checkIfConfiguredProperlyAndRequireFeedURL…`, `scheduleNextUpdateCheck…`), `Sparkle/SPUUpdaterSettings.m`, `Sparkle/SUHost.m`, `Sparkle/SPUExtractSignedFeed.m`, `Sparkle/SPUUserAgent+Private.m`, `Sparkle/SPUUpdater.h`, `Sparkle/SPUUpdaterDelegate.h`, `Sparkle/SPUStandardUserDriver.h`, `Sparkle/SPUStandardUserDriverDelegate.h`, `Sparkle/SPUUserUpdateState.h`, `generate_appcast/main.swift`, `generate_appcast/ArchiveItem.swift`, `generate_appcast/Appcast.swift`, `generate_appcast/FeedXML.swift`, `sign_update/main.swift`, `generate_keys/main.swift`, `common_cli/Signing.swift` — all under https://github.com/sparkle-project/Sparkle/tree/2.10.1
- Sparkle license: https://github.com/sparkle-project/Sparkle/blob/2.10.1/LICENSE

Homebrew:
- `auto_updates` stanza: https://docs.brew.sh/Cask-Cookbook
- `--greedy`, `--greedy-auto-updates`, `HOMEBREW_UPGRADE_GREEDY`: https://docs.brew.sh/Manpage

GitHub:
- `/releases/latest/download/<asset>` links: https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases
- Latest release excludes drafts and prereleases: https://docs.github.com/en/rest/releases/releases#get-the-latest-release
- Redirect chain to `release-assets.githubusercontent.com`: observed with `curl -sIL https://github.com/murathanbakti/nubrix/releases/latest/download/Nubrix-0.1.2.zip.sha256` on 2026-11-03.

Apple:
- Code signing requirement language (Developer ID OIDs, `anchor apple generic`): https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html
- `kSecCodeInfoTimestamp` (secure timestamp, vs `kSecCodeInfoTime`): https://developer.apple.com/documentation/security/kseccodeinfotimestamp
- `SecCodeCheckValidity`: https://developer.apple.com/documentation/security/1395700-seccodecheckvalidity
- Build settings (`INFOPLIST_KEY_*` covers Apple keys; `ENABLE_USER_SCRIPT_SANDBOXING`): https://developer.apple.com/documentation/xcode/build-settings-reference

Repository (at `2b98480`): `Nubrix.xcodeproj/project.pbxproj`, `Nubrix/Info.plist`, both entitlements files, `scripts/{sign-release,verify-bundle,package-release,notarize-release,install-local,install-hooks,setup-release-signing,run-tests}.sh`, `.github/workflows/{release,build}.yml`, `packaging/homebrew/nubrix.rb.template`, `NubrixHelper/main.swift`, `Nubrix/Features/Updates/*`, `Nubrix/Features/Inbox/*`, `Nubrix/Features/Agents/AgentEventServer.swift`.
