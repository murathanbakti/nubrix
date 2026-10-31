# Supply chain: committed `mediaremote-adapter` binaries

Nubrix reads system now-playing data through [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3-Clause, see `THIRD_PARTY_LICENSES`). The built artifacts are committed in `mediaremote-adapter/` and were not built by this repository's tooling. Their upstream tag and commit were not recorded when they were added, so the provenance is unproven.

## What is committed

| File | Use | SHA-256 |
|---|---|---|
| `mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter` | embedded in `Contents/Frameworks`, loaded by `/usr/bin/perl` | `91eb19837ca9f2779e476dc8e67d12bc28331dd557c87a19b0e45463c739c2fc` |
| `mediaremote-adapter/MediaRemoteAdapterTestClient` | copied into `Contents/Resources`, run by `helpers/MediaChecker.swift` | `f177cc4a7d79ea5d70f330eac6266884527039196215738373ea813034285c2a` |
| `mediaremote-adapter/mediaremote-adapter.pl` | Perl loader used by `NowPlayingController.swift` and `MediaChecker.swift` | `9ac5ed4532ad78431a85dd30e353efeca84391c4b84c760de74399c09cc2f2ca` |

Both binaries are ad-hoc signed (`com.vandenbe.MediaRemoteAdapter`, no Team ID). Because Release builds run with the hardened runtime, the app carries `com.apple.security.cs.disable-library-validation` (`Nubrix/Nubrix.release.entitlements`) so that dyld accepts this framework. This means the app will load any code-signed library placed at the paths it opens, so the integrity of this directory matters.

## Check the committed files

```sh
shasum -a 256 mediaremote-adapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  mediaremote-adapter/MediaRemoteAdapterTestClient mediaremote-adapter/mediaremote-adapter.pl
codesign -dv mediaremote-adapter/MediaRemoteAdapter.framework
```

Compare the output with the table above. A mismatch means the files changed since this note was written.

## Rebuild and compare

1. Clone `https://github.com/ungive/mediaremote-adapter` and check out a release tag. Record the tag and commit hash here.
2. Build with the upstream instructions (CMake, Xcode command line tools), for the same architectures the committed framework contains (`lipo -archs`).
3. Sign ad hoc (`codesign -f -s - <bundle>`).
4. Compare the Mach-O `__TEXT` and `__DATA` segments with the committed copy (`otool -l`, or `codesign -dvvv` for the cdhash). The signature and build paths differ, so a byte-for-byte match is not expected.
5. If the rebuild matches, replace the committed files with the rebuilt ones in a reviewed commit, and update the hashes and the tag above.

## Open items

- Record the upstream tag and commit that produced the current binaries.
- Verify the SHA-256 of the framework and test client in a build phase, or build them in CI from the pinned tag.
