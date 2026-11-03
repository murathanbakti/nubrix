# Troubleshooting

Common problems and how to fix them. For setup, see the [README](../../README.md).

## macOS says Nubrix cannot be opened

Or that it is "damaged" or from an unidentified developer.

Click "Done" ("Cancel" on macOS 14), not "Move to Trash", then see [First launch and Gatekeeper](../../README.md#first-launch-and-gatekeeper). This should not happen with 0.1.1 or later; run `brew upgrade --cask nubrix` or install the latest release.

## I clicked Move to Trash and Nubrix is gone

Run `brew reinstall --cask nubrix` (Homebrew still lists it as installed), or install again with the method you used before. Your settings and the hooks in `~/.config/nubrix` are kept.

## Keychain or permission prompts after an update

The Keychain asks for your password, or Camera, Calendar, Accessibility, Automation or Full Disk Access is asked again. Or Full Disk Access looks on in System Settings but does not work.

macOS ties every grant, and the Keychain access of the GitHub token, to the app's code signature. These are different signatures:

- a Developer ID release (from GitHub or Homebrew)
- a local build from `scripts/install-local.sh` (Apple Development certificate)
- an Xcode Debug build

If you switch between them, macOS treats the grant as missing: dialogs come back and Full Disk Access shows as on without working. Releases from 0.1.1 on keep the same Developer ID signature across updates, so updating a release over a release does not do this. Updating from 0.1.0 (ad-hoc signed, a new signature with every build) does it once.

Fix: in System Settings, Privacy & Security, turn the switch for Nubrix off and on again (or remove Nubrix with the minus button and add it again). For the Keychain item, click "Always Allow". Your GitHub token is not lost.

Debug builds and the unit-test host use their own bundle id `dev.nubrix.app.debug` and show as "Nubrix Debug". They have their own container (`~/Library/Containers/dev.nubrix.app.debug`), preferences and grants, so they never disturb the installed app.

Local builds made with `scripts/install-local.sh` are signed with a team-based designated requirement (`anchor apple generic and identifier "dev.nubrix.app" and certificate leaf[subject.OU] = "<team>"`). A grant made by a local build keeps working after you install a release of the same team. The other direction (release grant, then a local build) still needs a re-toggle until releases are signed with the same requirement.

To check which signature is installed:

```sh
codesign -d -r- /Applications/Nubrix.app
```

To see why macOS asks or ignores a grant, watch the permission daemon while you use the feature:

```sh
log stream --predicate 'subsystem == "com.apple.TCC" AND (eventMessage CONTAINS "AUTHREQ_PROMPTING" OR eventMessage CONTAINS "Failed to match")'
```

"Failed to match existing code requirement" means the grant belongs to another signature. "AUTHREQ_PROMPTING" is a real dialog for the permission that follows.

Last resort, if toggling does not help: `tccutil reset All dev.nubrix.app` forgets every grant of the app (for a Debug build, `dev.nubrix.app.debug`). macOS then asks again for each permission.

Version 0.1.1 and earlier had an onboarding that asked for camera, calendar, Accessibility and Full Disk Access up front, and restarted when you used "Quit & Reopen" during it. Update to 0.1.2 or later: `brew upgrade --cask nubrix`.

## Claude sign-in needed

The Home card or the Claude tab says "Claude sign-in needed: claude auth login".

The Claude Code CLI is signed out. Run `claude auth login` in a terminal; the card updates on the next refresh (open the notch on Home or the Claude tab). "Plan usage needs a Claude subscription" means an API-key login or an account without plan limits; "Claude Code not found" means `claude` is not in one of the [fixed locations](CLAUDE-CODE.md#official-plan-usage-claude-usage) Nubrix checks; "Update Claude Code to see plan usage" means your CLI version has no free local `/usage` command.

## No Claude sessions show up

Or the info button in the Claude tab lists problems.

Re-run the hook installer (`bash /Applications/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh`, or `scripts/install-hooks.sh` from a source checkout) and compare `~/.claude/settings.json` with the snippet it prints: the commands must point at `~/.config/nubrix/bin/...` and exist. Nubrix must be running. Claude Code reads hooks at session start, so start a new session after changing settings.

## Approvals do not appear in the notch

They need the `nubrix-permission` entry under `PermissionRequest` in your settings (not part of the plugin), the toggle in Settings, Notifications, and a running Nubrix. Claude's own questions and plan approvals are intentionally not shown there. If no notch can show the card (for example the notch is hidden for a fullscreen app, see Settings, Media, "Full screen behavior"), Claude Code asks in its own dialog.

## A screenshot is missing from Vitrin

You dragged it out of the macOS floating preview.

macOS writes a screenshot file only after the floating preview closes on its own. If you drag the preview somewhere or swipe it away, no file is written, so Vitrin has nothing to read (it says so on the Screenshots filter). Let the preview finish, or turn off "Show Floating Thumbnail" in the Screenshot app's Options (Shift-Command-5). Also check that Settings, Vitrin has the screenshot folder allowed.

## Vitrin says it is locked

The keychain prompt for the Vitrin key was denied, or the keychain is locked.

Nothing is lost and nothing was deleted. In Settings, Vitrin, click Retry and choose Allow or Always Allow in the keychain prompt. If the keychain is locked, unlock it (it normally unlocks when you log in) and click Retry. After you switch between a build you made yourself and a release, macOS asks once; "Always Allow" ends it. See [Privacy and security](PRIVACY-AND-SECURITY.md#vitrin).

## Vitrin history was reset

Vitrin says its history was reset because the encryption key is no longer in your keychain.

The key "Nubrix Vitrin history key" was missing from the login keychain, for example because it was deleted in Keychain Access, or because you are using a new user account or a new keychain. Without the key the old history cannot be decrypted, so it was removed and a new key was made. New copies are saved as usual. The message appears once.

## Nothing new appears in Vitrin

Check that Vitrin and the capture type are on and the frontmost app is not in the excluded list. On macOS 15.4 and later, check System Settings, Privacy & Security, Paste from Other Apps: with "Ask", Vitrin shows a pill with "Save Copied Item" and "Allow in Settings…" instead of reading in the background; with "Deny" it saves nothing. Text that looks like a credential is never stored.

## Music is not detected

Pick the source in Settings, Media. "Now Playing" uses the bundled MediaRemote adapter (run through `/usr/bin/perl`); on macOS versions where that access was removed, Nubrix does not switch to Apple Music by itself. It asks once which music source to use; you can change it later in Settings, Media. Spotify and Apple Music need the Automation permission (System Settings, Privacy & Security, Automation), which macOS asks for only after you pick that source. Settings, Permissions shows whether it is granted (only while that app is running). YouTube Music needs the desktop app's API server on `localhost:26538`.

## The notch is not visible

Check Settings, General: "Show on all displays" and "Automatically switch displays" decide which display shows it. On a Mac without a notch the bar is a strip at the top centre; its height is set there too. Settings, Media, "Full screen behavior" can hide it while an app is fullscreen. If you turned off the menu bar icon ("Show menu bar icon"), the Settings window may be hard to reach, so check that first.

## Nubrix asks for Accessibility although it is already on

macOS ties the switch to the exact signature of the app that was added; see [Keychain or permission prompts after an update](#keychain-or-permission-prompts-after-an-update). In System Settings, Privacy & Security, Accessibility, turn Nubrix off and on again, or select it, remove it with the minus button and add it again. Then turn "Replace system HUD" on again if Nubrix switched it off. The entry is called "Nubrix", not "NubrixHelper".

## Notifications from other apps do not appear

Check Settings, Notifications, Other apps: the status must say Ready and the app must be ticked. Only notifications that arrive after you turned the feature on are shown. If it says Full Disk Access is needed, click "Grant Access…" and follow the guide; if Nubrix is already on in the Full Disk Access list but the guide keeps waiting, use "Restart Nubrix" in the guide. After you turn Nubrix on, macOS offers "Quit & Reopen"; Nubrix then reopens the place you started from with an "Access granted" panel. A different signature (see above) or updating from 0.1.0 can drop the grant: turn Nubrix off and on again, or remove it with the minus button and add it again. Notifications from the app in front are skipped unless you turn that option off, and the app must still deliver its notifications to Notification Center ("Show in Notification Center" on in System Settings, Notifications).

## The volume and brightness HUDs did not change

"Replace system HUD" needs Accessibility access for Nubrix (System Settings, Privacy & Security, Accessibility; the entry is "Nubrix", the helper does not appear separately). If access is missing at launch, Nubrix turns the option off. Settings, Permissions shows the current state.
