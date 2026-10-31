# Contributing to Nubrix

Thanks for your interest. Nubrix is a small personal project, so keep changes focused.

## Before you start

- Search existing issues and pull requests first.
- For anything larger than a bug fix, open an issue to discuss it before writing code.

## Setup

1. Fork and clone the repository.
2. Use macOS 14 or later with Xcode 26.
3. Build:
   ```sh
   xcodebuild -project Nubrix.xcodeproj -scheme Nubrix -configuration Debug \
     -derivedDataPath build -destination 'platform=macOS' build
   ```

## Where things live

- Nubrix code is in `Nubrix/Features/`. It is a file-system synchronized group in Xcode, so new files are picked up automatically; avoid editing `project.pbxproj` by hand.
- Files under the rest of `Nubrix/` come from the upstream project (see Credits in the README). Keep edits there small so upstream changes can still be merged.
- Everything carries the Nubrix name: targets, Swift types, preference keys and identifiers.

## Pull requests

- Create a branch from `nubrix`, make the change, and make sure the project builds.
- Describe what changed and why, and include screenshots or a screen recording for UI changes.
- Link the issue it fixes with `closes #123`.
- Do not include secrets, personal data or build output.

## Reporting bugs and requesting features

Open an issue with your macOS version, Nubrix version, steps to reproduce, and expected versus actual behavior. For security problems read [SECURITY.md](SECURITY.md) first.

## License

By contributing you agree that your contribution is licensed under GPL-3.0, the same as the project.
