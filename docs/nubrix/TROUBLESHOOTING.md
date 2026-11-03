# Troubleshooting

Common problems and how to fix them. For setup, see the [README](../../README.md).

## macOS says Nubrix cannot be opened

Or that it is "damaged" or from an unidentified developer.

Click "Done" ("Cancel" on macOS 14), not "Move to Trash", then see [First launch and Gatekeeper](../../README.md#first-launch-and-gatekeeper). This should not happen with 0.1.1 or later; run `brew upgrade --cask nubrix` or install the latest release.

## I clicked Move to Trash and Nubrix is gone

Run `brew reinstall --cask nubrix` (Homebrew still lists it as installed), or install again with the method you used before. Your settings and the hooks in `~/.config/nubrix` are kept.

## Keychain or permission prompts after an update

The Keychain asks for your password, or Camera, Calendar, Accessibility or Full Disk Access is asked again.

macOS ties Keychain access and permission grants to the app's code identity. Releases from 0.1.1 on keep the same Developer ID identity across updates, so this happens once when you update from 0.1.0 (ad-hoc signed, a new identity with every build) and not again. Click "Always Allow" for the Keychain item, and grant the permissions again if macOS asks. Your GitHub token is not lost. If you build from source, sign with your own certificate to stop this (see [From source](INSTALL.md#from-source)); after switching, macOS asks one last time.

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

Check that Vitrin and the capture type are on, the frontmost app is not in the excluded list, and, on macOS versions that ask, that pasteboard access for Nubrix is allowed. Text that looks like a credential is never stored.

## Music is not detected

Pick the source in Settings, Media. "Now Playing" uses the bundled MediaRemote adapter (run through `/usr/bin/perl`); on macOS versions where that access was removed, Nubrix selects Apple Music instead and you can use the Spotify, Apple Music or YouTube Music controllers. Spotify and Apple Music need the Automation permission (System Settings, Privacy & Security, Automation). YouTube Music needs the desktop app's API server on `localhost:26538`.

## The notch is not visible

Check Settings, General: "Show on all displays" and "Automatically switch displays" decide which display shows it. On a Mac without a notch the bar is a strip at the top centre; its height is set there too. Settings, Media, "Full screen behavior" can hide it while an app is fullscreen. If you turned off the menu bar icon ("Show menu bar icon"), the Settings window may be hard to reach, so check that first.

## Nubrix asks for Accessibility although it is already on

macOS ties the switch to the exact build of the app that was added. After you install a different build of Nubrix (for example a release over a build you made yourself), the old entry still shows as on but is not trusted. In System Settings, Privacy & Security, Accessibility, select Nubrix, remove it with the minus button and add it again with the plus button, then turn "Replace system HUD" on again if Nubrix switched it off.

## Notifications from other apps do not appear

Check Settings, Notifications, Other apps: the status must say Ready and the app must be ticked. Only notifications that arrive after you turned the feature on are shown. If it says Full Disk Access is needed, click "Grant Access…" and follow the guide; if Nubrix is already on in the Full Disk Access list but the guide keeps waiting, use "Restart Nubrix" in the guide. Updating from 0.1.0 can drop the grant: remove Nubrix from the list with the minus button and add it again. Notifications from the app in front are skipped unless you turn that option off, and the app must still deliver its notifications to Notification Center ("Show in Notification Center" on in System Settings, Notifications).

## The volume and brightness HUDs did not change

"Replace system HUD" needs Accessibility access for Nubrix's helper (System Settings, Privacy & Security, Accessibility). If access is missing at launch, Nubrix turns the option off.
