# Controls tab and smaller alerts

Two changes, done in this order.

- **Part A:** the big cards that drop under the closed notch go away. Notifications, device batteries and everyday alerts keep only the one-line header beside the notch. The Notifications tab stays as it is.
- **Part B:** a new notch tab, **Controls**, to see and change sound output and input, volume, Bluetooth devices, drives, display brightness and keyboard backlight.

Mockup: [`docs/images/mockups/controls.html`](../../images/mockups/controls.html), rendered to `docs/images/controls.png` with `docs/images/mockups/render.sh controls`. The SwiftUI view follows the mockup's sizes, fonts and colors.

Build check after each part:

```sh
xcodebuild -project Nubrix.xcodeproj -scheme Nubrix -configuration Debug \
  -derivedDataPath ~/Library/Caches/Nubrix/DerivedData-controls -destination 'platform=macOS' -quiet build
```

Tests: `scripts/run-tests.sh`.

## Part A: remove the drop-down cards

Why: the cards are large and do not match the design (compare `docs/images/notifications.png`, where banners are one line beside the notch).

1. `Nubrix/ContentView.swift`
   - Delete `systemDropShowing`, `deviceBatteryDropShowing`, `everydayDropShowing`.
   - Delete the three branches that show `SystemNotificationDropBody`, `DeviceBatteryDropBody`, `EverydayAlertCard` (around line 454). The `else if coordinator.sneakPeek.show` branch now follows the permission prompt branch.
2. `Nubrix/Features/SystemNotifications/SystemNotificationViews.swift`
   - `SystemNotificationBannerView` always uses the inline header (`inlineHeader`). Delete `dropDownHeader` and the `style` property.
   - Delete `SystemNotificationDropBody` and any helper used only by it.
   - Delete the "Style" picker in the settings view (around line 282) and any text that describes the drop-down style.
3. `Nubrix/Features/SystemNotifications/SystemNotificationDefaults.swift`: delete `SystemNotificationStyle` and the `systemNotificationStyle` key.
4. `Nubrix/Features/FeatureToggles/DefaultsMigration.swift`: delete the `systemNotificationStyle` entry and its comment. Update `NubrixTests/Permissions/DefaultsMigrationTests.swift` so the tests that used `systemNotificationStyle` use another key from `previousDefaults` (for example `enableSneakPeek`, old value `false`) and still test the same behavior.
5. `Nubrix/Features/DeviceBattery/DeviceBatteryViews.swift`: delete `DeviceBatteryDropBody` and helpers only it uses. Keep `batteryRingTint` and `DeviceBatteryBannerHeader`.
6. `Nubrix/Features/Everyday/EverydayViews.swift`: delete `EverydayAlertCard` and helpers only it uses. Keep `EverydayAlertHeader`.
7. Search the whole repo (`Nubrix`, `NubrixTests`, `README.md`, `docs/`) for the removed names and for "drop-down", "Drops down", "like iPhone". Remove or reword what refers to the card. Leave `CHANGELOG.md` history alone. Unused strings in `Localizable.xcstrings` may stay.
8. Anything that only existed for the card (hover keeps it open, longer duration for the card, height logic) goes too. Do not change how the headers behave.

## Part B: Controls tab

### Tab wiring

- `Nubrix/enums/generic.swift`: add `case controls` to `NotchViews`, right after `home`.
- `Nubrix/Features/Tabs/NotchTabLayout.swift`:
  - `NotchTabCatalog.all`: `TabModel(label: "Controls", icon: "slider.horizontal.3", view: .controls)` right after Home.
  - `settingsTab(for: .controls)` returns `nil`, `isFeatureEnabled(.controls)` returns `true` (like Home). It can be hidden in Settings, Tabs.
  - Existing installs have a saved `notchTabOrder` without `.controls`; `computeOrdered` already appends it at the end. That is fine.
- Fix every `switch` over `NotchViews` (search the repo, tests included). In `ContentView` the open-notch switch gets `case .controls: ControlsTabView()`.
- Closed notch, tapping an everyday alert (`ContentView`, the `everyday.banner != nil` branch): for a sound output alert or a drive alert, also open the notch on the Controls tab, if that tab is visible. Look at how the other branches open the notch and pick a tab, and do it the same way. Other everyday alerts keep today's behavior. Telling the alert kinds apart may need a small field on `EverydayAlert` (for example `var opensControls: Bool`), set where sound output and drive alerts are made.

### New files in `Nubrix/Features/Controls/`

Add them to the Xcode project the same way other feature folders are (check whether the project uses file system synchronized groups; if it does, nothing to add).

**`AudioDevices.swift`**: CoreAudio device list. Reuse the helpers already in `Nubrix/Features/Everyday/EverydaySources.swift` (address, uint32, string, defaultDevice) and `SoundDevice` (`symbol`) in `EverydayAlert.swift` instead of writing new ones; move or widen them if needed.

- `struct AudioDeviceInfo: Identifiable, Equatable { id: AudioObjectID; uid; name; transport; symbol }`.
- `devices(input: Bool) -> [AudioDeviceInfo]`: `kAudioHardwarePropertyDevices`, keep devices with at least one stream in that scope (`kAudioDevicePropertyStreams`), skip hidden ones and Nubrix-irrelevant aggregate/virtual devices only if they are hidden (`kAudioDevicePropertyIsHidden`). Sort: built-in first, then by name.
- `setDefault(_ id: AudioObjectID, input: Bool)`: sets `kAudioHardwarePropertyDefaultOutputDevice` (and `kAudioHardwarePropertyDefaultSystemOutputDevice` for output) or `kAudioHardwarePropertyDefaultInputDevice`.
- Input volume: read and write `kAudioDevicePropertyVolumeScalar` in the input scope, main element first, then channels 1 and 2. `nil` when not settable (`AudioObjectIsPropertySettable`).

**`ControlsStore.swift`**: `@MainActor final class ControlsStore: ObservableObject`, `static let shared`.

- Published: `outputs`, `inputs`, `currentOutput`, `currentInput` (ids), `inputVolume: Float?`, `bluetoothOn: Bool`, `bluetooth: [ControlsBluetoothDevice]`, `drives: [DriveVolume]`, `busy: Set<String>` (Bluetooth addresses being connected or disconnected).
- `start()` / `stop()`, called from the view's `onAppear` / `onDisappear`. It only listens while the tab is on screen: CoreAudio listeners for `kAudioHardwarePropertyDevices`, default output and default input (reuse `AudioListeners` from `EverydaySources.swift`); `NSWorkspace` did-mount / did-unmount notifications for drives; a 3 second timer for Bluetooth. `start()` also calls `VolumeManager.shared.refresh()`, `BrightnessManager.shared.refresh()` and `KeyboardBacklightManager.shared.refresh()`.
- Bluetooth with IOBluetooth (the app already has the `com.apple.security.device.bluetooth` entitlement):
  - `bluetoothOn`: `IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON`.
  - Devices: `IOBluetoothDevice.pairedDevices()`. For each: name, `addressString`, `isConnected()`, an SF Symbol from the name and device class (reuse `DeviceBattery.kind.symbol` logic if it fits), battery from `DeviceBatterySource.snapshot(_:)?.lowest` when connected. Sort connected first, then by name.
  - `toggle(_ device)`: `openConnection()` or `closeConnection()` on a background queue (they block), address in `busy` meanwhile, refresh after.
  - `openBluetoothSettings()`: open `x-apple.systempreferences:com.apple.BluetoothSettings`.
  - Power cannot be switched with a public API; do not use private API. The header only shows the state and opens Bluetooth settings.
- Drives: `FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys:options: [.skipHiddenVolumes])`, read each with `DriveWatcher.read(_:)`, keep what is ejectable or removable, not internal and not a disk image (match the rules the drive alerts use). `eject(_ drive)`: reuse the eject code of `EverydayAlertStore` (`unmountAndEjectDevice` on a background queue; on failure show the existing "eject failed" alert).

**`ControlsTabView.swift`**: the layout of the mockup, content area 578 x 138.

- `HStack(spacing: 8)` of three cards, full height. Sound and Devices cards share the free width equally (214 each at 640 wide), Display card is 134 wide.
- Card style: `RoundedRectangle(cornerRadius: 12, style: .continuous)` filled `.white.opacity(0.06)` with a `.white.opacity(0.08)` 1 pt border, padding 8 x 10 (Display card 8), spacing 6. Same as the Claude usage card on Home.
- Text: header 12 semibold white; row names 11.5 medium, white when current or connected, else `white.opacity(0.72)`; meta 10 medium gray; section label 9.5 semibold uppercase `white.opacity(0.55)`. Percentages use the rounded design and monospaced digits.
- **Sound card**
  - Header: "Sound", then a two-part control "Output" / "Input" (10 semibold; selected part has `white.opacity(0.16)` fill, the whole thing `white.opacity(0.07)`, radius 7). `@State` mode, Output by default.
  - Slider row, 18 high: a button with `speaker.wave.2.fill` (or `speaker.slash.fill` when muted) that toggles mute (`VolumeManager.shared.toggleMuteAction()` must not pop the HUD here; if it does, add a quiet variant); a horizontal slider, 6 high, track `Color(white: 0.6).opacity(0.3)`, fill white; percent on the right. Output mode uses `VolumeManager.shared.rawVolume` and `setAbsolute`. Input mode uses `mic.fill` and `ControlsStore.inputVolume`; when it is `nil` the slider is dimmed and not draggable. Reuse an existing slider view from the HUD or music player if one fits; it must not show the system HUD or sneak peek while dragging.
  - Device rows, 21 high, radius 7: symbol, name, checkmark on the current device, current row filled `white.opacity(0.10)`. Tap selects. More than 3 rows scroll vertically without indicators.
- **Devices card**
  - Header: "Devices", then on the right "Bluetooth On" or "Bluetooth Off" with a chevron, gray 10 medium, a button that opens Bluetooth settings.
  - Bluetooth rows like the sound rows: symbol, name, then for connected devices the battery percent colored with `batteryRingTint` and a 6 pt green dot. On hover a row shows a small capsule button ("Disconnect" for connected, "Connect" otherwise) in place of the right side; not connected rows always show "Connect" in the mockup's gray capsule. While busy, a small `ProgressView` instead.
  - Bluetooth off: one gray row "Bluetooth is off". No paired devices: "No Bluetooth devices".
  - When drives are mounted: a "Drives" section label, then one row per drive: `externaldrive.fill`, name, "412 GB free" (`ByteCountFormatter`, file style), and an eject button (`eject.fill`).
  - The card's rows scroll vertically when they do not fit.
- **Display card**
  - Two vertical sliders side by side, 10 apart, centered: 50 x 104, radius 14, track `Color(white: 0.6).opacity(0.22)`, white fill from the bottom, a black symbol 9 pt above the bottom (`sun.max.fill`, `light.max` for the keyboard). Drag up and down (and click) to set. Under each a 10 medium gray label, "Display" and "Keyboard", that shows the percent while dragging.
  - Display uses `BrightnessManager.shared.rawBrightness` and `setAbsolute(value:)`; Keyboard uses `KeyboardBacklightManager.shared`. Calls over XPC: send at most one write every 50 ms while dragging, plus the final value. Do not trigger the sneak peek HUD.

### Tests

Add small unit tests where logic is pure: `NotchTabLayout.computeOrdered` with a saved order without `.controls` puts it last; `computeVisible` shows `.controls` by default. Update tests that list every `NotchViews` case.

### Docs

- README: mention the Controls tab where tabs are listed, and drop any mention of the drop-down card.
- `CHANGELOG.md`: an `## [Unreleased]` section at the top with Added (Controls tab) and Removed (drop-down cards).

## Part C: fixes and a clearer layout (after the first try)

The user tried Part B: display brightness did not work, keyboard light only partly worked, and the layout was hard to read. They also want the notch on their HDMI display, with an on/off switch in Settings.

### Causes found

- **Display brightness.** `NubrixHelper` always uses `CGMainDisplayID()`. On this Mac the main display is an external monitor, where `DisplayServicesGetBrightness` returns 1000 (fails); the built-in display (id 1) works. External monitors need DDC, which is out of scope.
- **Keyboard light.** `KeyboardBrightnessClient` in the helper hard-codes keyboard id `1`. `copyKeyboardBacklightIDs` returns the real id (here `95158272`). Also, writes during a drag are separate `Task`s that can land out of order.

### Fixes

1. Helper, screen brightness: pick the display to use once per call: the main display if DisplayServices can read it, else the built-in display (`CGDisplayIsBuiltin`) from `CGGetOnlineDisplayList`, else the IOKit path as today. Apply the same choice to `isScreenBrightnessAvailable`, `currentScreenBrightness` and `setScreenBrightness`. The brightness keys HUD gets the fix too.
2. Helper, keyboard: read the ids with `copyKeyboardBacklightIDs` (an `NSArray` of numbers) and use the first, falling back to `1`. Set with `setBrightness:fadeSpeed:commit:forKeyboard:` (fade speed 0, commit `true`) when the client has it, so auto-adjust does not undo the change; else `setBrightness:forKeyboard:`. Check `brightnessForKeyboard:` reads back the value.
3. App: brightness and keyboard writes from a drag go through one serial path where only the newest value is sent (latest wins, at most one call in flight). `isScreenBrightnessAvailable` / `isKeyboardBrightnessAvailable` decide whether the row is enabled; a disabled row is dimmed and says "Not available" in place of the value.

### Layout v2 (see the mockup)

Two cards side by side, content 578 x 138.

- **Levels** (left, 288 wide): header "Levels", then four rows 22 high, spacing 5: icon (16 wide), name (11 medium, `white.opacity(0.78)`, 84 wide), horizontal slider with a 12 pt white knob, value (rounded 11 semibold, 32 wide, right aligned). Rows: Volume (`speaker.wave.2.fill`; tapping the icon mutes, `speaker.slash.fill` when muted), Microphone (`mic.fill`, input volume of the current input; dimmed "Fixed" when not settable), Brightness (`sun.max.fill`), Keyboard light (`light.max`). No vertical sliders.
- **List** (right, the rest): a tab bar at the top with four equal parts, Output, Input, Bluetooth, Drives (10.5 semibold; selected part `white.opacity(0.16)` on `white.opacity(0.07)`, radius 8). Under it rows 24 high: icon, name (11.5 medium white) and a second line (9.5 medium) with the state, then a button on the right.
  - Output / Input: current device has the row fill `white.opacity(0.10)`, green "Playing here" (Input: "In use") and a checkmark; others show a "Use" button.
  - Bluetooth: connected devices say green "Connected · 82%" (percent only when known) and a "Disconnect" button; others say "Not connected" and a "Connect" button; while busy, "Connecting…" / "Disconnecting…" and a small spinner. A last row "Bluetooth settings…" opens settings. When Bluetooth is off: "Bluetooth is off" and the settings row.
  - Drives: name, "412 GB free", an "Eject" button. Empty: "No drives connected".
  - Buttons: 10 semibold, capsule, padding 2 x 8; primary `white.opacity(0.14)` white text, secondary `white.opacity(0.07)` with `white.opacity(0.70)` text. Rows scroll when there are more than three.
  - The selected list tab is remembered (`@AppStorage` or a Defaults key).

### Notch on every display

`showOnAllDisplays` and its toggle ("Show on all displays", Settings, General) already exist; the user's installed app has it on, yet they report the notch does not appear on their HDMI display. Check the multi-display path in `NubrixApp.swift` (window per screen, `adjustWindowPosition`, screen change notifications, and what a screen without a camera housing gets): with the setting on, every connected screen, including one without a notch, must get its own notch window at the top center, and turning it off must leave only the preferred display. Make the toggle's label and help text plain, for example "Show the notch on every display" with "Also on external displays connected with HDMI, USB-C or AirPlay." Fix what is broken; do not rewrite what works.

## Part D: a taller Controls tab and Bluetooth batteries

Feedback on v2 (screenshot): the list card overflows, the last row ("Playing here") is cut off and needs scrolling, and everything is small. The user wants it bigger and easier to see, and battery levels for Bluetooth devices.

- **Taller notch on the Controls tab only.** The open notch is a fixed 640 x 190 (`openNotchSize`, `windowSize` in `Nubrix/sizing/matters.swift`). On the Controls tab the open notch is 640 x 270 (content about 218 high); every other tab stays 190. Animate the change like the open animation. Find the cleanest way: the window must be tall enough for the larger size, and the extra transparent area must not catch clicks, hovers or drags meant for apps below when the notch is closed or on another tab (check how hover/hit areas and `ignoresMouseEvents` work today, and the drag detector region). Other tabs must look and behave exactly as before.
- **Bigger, clearer Controls layout** using the new height:
  - Levels rows 34 high: icon 18, name 12.5 medium, slider track 8 high with a 16 pt knob, value 12.5 rounded semibold. Header "Levels" 13 semibold.
  - List: tab bar 12 semibold, about 24 high. Rows 34 high: icon 16, name 13 medium, state line 11 medium, buttons 11 semibold with padding 3 x 10. Four rows fit without scrolling; scroll only beyond that.
  - Keep the colors and structure of v2.
- **Bluetooth batteries.** Show what `DeviceBatterySource` can read (IOBluetooth battery keys, then the HID fallback). Keep the parts of a device (`DeviceBattery.parts`), not only the lowest. Bluetooth tab state line: "Connected · 82%" for one part, "Connected · L 80% · R 82% · Case 40%" for AirPods-style devices (use the existing part labels), each percent colored with `batteryRingTint`. A small battery symbol before the text is fine. On the Output and Input tabs, a Bluetooth audio device (match by name or address) shows the same battery text after "Playing here" or in its state line. Refresh with the existing 3 second Bluetooth timer.

## Part E: a polished, Control Center style layout

Feedback on Part D (screenshot): it works (AirPods show "L 83% · R 83%"), but the design looks crude: heavy boxed cards, a big empty area in Levels, default-looking sliders, cluttered "Use" buttons. Mockup v3: `docs/images/mockups/controls.html` / `docs/images/controls.png`. Keep the 640 x 270 notch and all behavior; only the look changes.

- **No cards.** Two columns on the black notch, split by a 1 pt hairline `white.opacity(0.08)` (inset 6 top, 10 bottom). Left column 262 wide (padding right 18), right column the rest (padding left 16).
- **Left: two groups, "Sound" and "Display"**, 12 apart. Group label 11 semibold `white.opacity(0.55)`, 6 above its sliders; sliders 6 apart.
- **Capsule slider** (new reusable view, replaces the thin track + knob): 30 high, fully rounded. Track `white.opacity(0.10)`. Fill `white.opacity(0.92)`, fully rounded too, at least 30 wide when the value is above 0 (so the icon sits inside it), animated with a short spring. Symbol 14 pt at 10 from the left: dark (`Color(white: 0.11)`) when the fill covers it, else `white.opacity(0.8)`. Value on the right (rounded 11 semibold, monospaced digits, 11 from the right): dark when the fill reaches past the text (fill width > width − 44), else `white.opacity(0.55)`. Drag anywhere to set (relative to where the drag started, like Control Center); click sets directly. Volume: tapping the symbol mutes, `speaker.slash.fill` when muted, value "Muted". Keyboard at 0: "Off". Not available: whole slider at 40% opacity, value "Not available", no hit testing. Microphone not settable: "Fixed".
  - Rows: Sound → Volume (`speaker.wave.2.fill`, changes with level like macOS: wave.1 / wave.2 / wave.3), Microphone (`mic.fill`). Display → Brightness (`sun.max.fill`), Keyboard (`light.max`).
- **Right: segmented control** at the top left (not stretched): container `white.opacity(0.06)`, radius 9, padding 2; parts 11 semibold, padding 3 x 10, radius 7; selected `white.opacity(0.14)` white text, others `white.opacity(0.5)`. Animate the selection with `matchedGeometryEffect`.
- **Rows**, 38 high, radius 10, spacing 1, no buttons:
  - Leading 28 pt circle: `white.opacity(0.10)` with a `white.opacity(0.85)` symbol; selected or connected: the app accent color (the color Nubrix already uses for accents; find it) with a white symbol.
  - Name 12.5 medium white; second line 10.5 medium `white.opacity(0.5)`: the kind (Built-in, Bluetooth, HDMI, DisplayPort, USB, AirPlay, Virtual; from the CoreAudio transport type) for Output/Input; "Connected" / "Not connected" / "Connecting…" / "Disconnecting…" for Bluetooth; "412 GB free" for Drives.
  - Trailing: batteries as plain text pairs, "L 83%  R 83%  Case 41%" (letter `white.opacity(0.4)`, number `white.opacity(0.7)` 10.5 semibold; number in orange/red only when low, via `batteryRingTint` below 21%). For a single part just "82%".
  - Whole row is the button. Hover: `white.opacity(0.06)` fill, plus a quiet trailing word where an action happens: "Connect" / "Disconnect" (Bluetooth), nothing on Output/Input (tapping selects). Drives: a 22 pt round eject button (`eject.fill`, `white.opacity(0.10)`), visible always. Busy: small spinner in place of the trailing content.
  - Bluetooth: last row "Bluetooth Settings…" in `white.opacity(0.5)`, no circle fill. Empty states centered, 11 medium `white.opacity(0.45)`.
- Remove the old Levels/List card views, their styles and anything else no longer used.

## Part F: Wi-Fi

The user wants the Controls tab to feel like the iPhone's Control Center, so Wi-Fi goes in too. Mockup: `docs/images/mockups/controls.html` (Wi-Fi tab selected).

- **Tabs:** Wi-Fi, Bluetooth, Output, Input, Drives (Wi-Fi first). Parts padding 3 x 8 so five fit. Existing saved tab values keep working.
- **CoreWLAN** (`CWWiFiClient.shared().interface()`), in a new `Nubrix/Features/Controls/WiFiControls.swift` used by `ControlsStore`. Only active while the tab is on screen, like the rest of the store. Listen with `CWWiFiClient` event delegate (power, SSID, link) or poll every 3 s, whichever is reliable in the sandbox.
- **Rows:**
  - First row: "Wi-Fi" (12.5 semibold) and a switch (accent color, 34 x 20) that calls `setPower(_:)`. If that throws (sandbox), show the error once as the row's second line ("Can't switch Wi-Fi from here") and open Wi-Fi settings (`x-apple.systempreferences:com.apple.wifi-settings-extension`) instead.
  - Current network: accent circle with `wifi`, name, "Connected · <IPv4 of the Wi-Fi interface>", signal bars from RSSI (4 bars: > −55, > −67, > −75, else 1). When Wi-Fi is off: "Wi-Fi is off" row.
  - "Other networks" label and the scan results (`scanForNetworks(withName: nil)` on a background queue, at most every 20 s, sorted by RSSI, duplicates by SSID removed, current one excluded): circle with `wifi`, name, "Secured" / "Open", signal bars. Hover shows "Join". Open networks join with `associate(to:password: nil)`; secured ones open Wi-Fi settings (we never ask for or handle passwords). Spinner while joining.
  - Last row "Wi-Fi Settings…".
- **Network names need Location access** on current macOS (SSID and scan results come back empty without it). Do not ask on launch. When names are unavailable, the current network row says "Connected" with the IP, and the list shows one row: "Show network names" with the second line "Needs Location access"; tapping it asks for When-In-Use location authorization (`CLLocationManager`). If denied, the row opens Privacy & Security, Location Services. Add `NSLocationUsageDescription` / `NSLocationWhenInUseUsageDescription` ("Nubrix shows the names of Wi-Fi networks in the Controls tab. macOS treats network names as location data.") and the `com.apple.security.personal-information.location` entitlement to the app (not the helper). Add Location to the Permissions settings tab (live status, Grant) the way the others are done, and to `docs/nubrix/PERMISSIONS-AND-SETTINGS.md`, `docs/nubrix/PRIVACY-AND-SECURITY.md` / `SECURITY.md` where entitlements are listed, and `scripts/verify-bundle.sh` if it checks the entitlement list.
- CHANGELOG `[Unreleased]`: Added (Wi-Fi in Controls), Security (new location entitlement and usage text, only asked when you tap "Show network names").

## Part G: quick toggles and a Bluetooth switch

Feedback: make it easier to use; Wi-Fi has an on/off switch, Bluetooth does not. Mockup: `docs/images/mockups/controls.html` (v4).

### Left column, top to bottom

- **Quick toggles**, iPhone style: a row of four 44 pt circles with a 10 medium label under each (`white.opacity(0.6)`), spread across the column.
  - **Wi-Fi** (`wifi`): accent when on, `white.opacity(0.12)` when off (`wifi.slash`). Click switches power. Also selects the Wi-Fi list on the right.
  - **Bluetooth** (`bluetooth` style symbol; use a custom shape or the closest SF Symbol available on macOS 14, check): accent when on. Click switches power (see below). Also selects the Bluetooth list.
  - **Sound** (`speaker.wave.2.fill`): a mute switch. Not muted: `white.opacity(0.12)`. Muted: red (`Color.red.opacity(0.9)`), `speaker.slash.fill`, label "Muted".
  - **Mic** (`mic.fill`): mutes the current input (set input volume to 0 and remember the level to restore; if the input volume can't be set, the button is dimmed and does nothing). Muted: red, `mic.slash.fill`, label "Mic off".
  - Press feedback: scale 0.94 on press, spring. Busy (power change in flight): small spinner over the symbol. Help tooltip on each.
- **Three capsule sliders**, 8 apart, no group labels: Volume, Brightness, Keyboard light (same component and rules as Part E). The microphone level slider moves to the top of the Input list.

### Right column

- Tabs: Wi-Fi, Bluetooth, Output, Input, and Drives only while a drive is mounted (falls back to Wi-Fi if Drives disappears while selected).
- Wi-Fi list: remove the "Wi-Fi" switch row (the quick toggle replaces it). Bluetooth list: when off, one row "Bluetooth is off" with hint "Turn On".
- Input list: first a capsule slider for the microphone level (same component), then the input devices.

### Bluetooth power

No public API. Use the private `IOBluetoothPreferenceGetControllerPowerState() -> Int32` and `IOBluetoothPreferenceSetControllerPowerState(Int32)` from IOBluetooth.framework (looked up with `dlsym`, both symbols are present on this Mac), the same way the helper already uses DisplayServices and CoreBrightness. Calling them from a process without a Bluetooth usage description gets it killed by TCC, so:
1. First try from the app process (it has `NSBluetoothAlwaysUsageDescription` and the Bluetooth entitlement). Check at runtime in the Debug build that Get returns the right state in the sandbox (read only).
2. If the sandbox blocks it, move both calls into `NubrixHelper` (not sandboxed) behind new XPC methods, and give the helper what TCC needs.
3. If neither works, the Bluetooth quick toggle opens Bluetooth settings, with the tooltip "Open Bluetooth settings".
Do not actually turn Bluetooth off while testing (the user's AirPods and keyboard are connected); verifying Get is enough. Document the private API use in `docs/nubrix/PRIVACY-AND-SECURITY.md` next to the existing DisplayServices/CoreBrightness notes, and CHANGELOG.
