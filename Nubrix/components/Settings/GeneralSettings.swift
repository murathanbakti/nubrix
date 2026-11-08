import Defaults
import LaunchAtLogin
import SwiftUI

struct GeneralSettings: View {
    @State private var screens: [(uuid: String, name: String)] = NSScreen.screens.compactMap { screen in
        guard let uuid = screen.displayUUID else { return nil }
        return (uuid, screen.localizedName)
    }
    @ObservedObject var coordinator = NubrixCoordinator.shared

    @Default(.gestureSensitivity) var gestureSensitivity
    @Default(.minimumHoverDuration) var minimumHoverDuration
    @Default(.nonNotchHeight) var nonNotchHeight
    @Default(.nonNotchHeightMode) var nonNotchHeightMode
    @Default(.notchHeight) var notchHeight
    @Default(.notchHeightMode) var notchHeightMode
    @Default(.showOnAllDisplays) var showOnAllDisplays
    @Default(.automaticallySwitchDisplay) var automaticallySwitchDisplay
    @Default(.enableGestures) var enableGestures
    @Default(.openNotchOnHover) var openNotchOnHover
    @Default(.showBatteryIndicator) var showBatteryIndicator

    var body: some View {
        Form {
            systemSection
            sizingSection
            behaviorSection
            gestureSection
            batterySection
        }
        .toolbar {
            Button("Quit app") {
                NSApp.terminate(self)
            }
            .controlSize(.extraLarge)
        }
        .settingsPage(.general)
        .onChange(of: openNotchOnHover) {
            if !openNotchOnHover {
                enableGestures = true
            }
        }
    }

    private var systemSection: some View {
        Section {
            Defaults.Toggle(key: .menubarIcon) {
                Text("Show menu bar icon")
            }
            LaunchAtLogin.Toggle("Launch at login")
            Defaults.Toggle(key: .showOnAllDisplays) {
                Text("Show the notch on every display")
                Text("Also on external displays connected with HDMI, USB-C or AirPlay.")
            }
            .onChange(of: showOnAllDisplays) {
                NotificationCenter.default.post(
                    name: Notification.Name.showOnAllDisplaysChanged, object: nil)
            }
            Picker("Preferred display", selection: $coordinator.preferredScreenUUID) {
                ForEach(screens, id: \.uuid) { screen in
                    Text(screen.name).tag(screen.uuid as String?)
                }
            }
            .onChange(of: NSScreen.screens) {
                screens = NSScreen.screens.compactMap { screen in
                    guard let uuid = screen.displayUUID else { return nil }
                    return (uuid, screen.localizedName)
                }
            }
            .disabled(showOnAllDisplays)
            Defaults.Toggle(key: .automaticallySwitchDisplay) {
                Text("Automatically switch displays")
            }
            .onChange(of: automaticallySwitchDisplay) {
                NotificationCenter.default.post(
                    name: Notification.Name.automaticallySwitchDisplayChanged, object: nil)
            }
            .disabled(showOnAllDisplays)
        } header: {
            Text("System")
        }
    }

    private var sizingSection: some View {
        Section {
            Picker("Notch height on notch displays", selection: $notchHeightMode) {
                Text("Match real notch height")
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text("Match menu bar height")
                    .tag(WindowHeightMode.matchMenuBar)
                Text("Custom height")
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: notchHeightMode) {
                switch notchHeightMode {
                case .matchRealNotchSize:
                    notchHeight = 38
                case .matchMenuBar:
                    notchHeight = 44
                case .custom:
                    notchHeight = 38
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }
            if notchHeightMode == .custom {
                Slider(value: $notchHeight, in: 15...45, step: 1) {
                    HStack {
                        Text("Custom height")
                        Spacer()
                        Text("\(notchHeight, specifier: "%.0f")")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: notchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
            Picker("Notch height on other displays", selection: $nonNotchHeightMode) {
                Text("Match menu bar height")
                    .tag(WindowHeightMode.matchMenuBar)
                Text("Match real notch height")
                    .tag(WindowHeightMode.matchRealNotchSize)
                Text("Custom height")
                    .tag(WindowHeightMode.custom)
            }
            .onChange(of: nonNotchHeightMode) {
                switch nonNotchHeightMode {
                case .matchMenuBar:
                    nonNotchHeight = 24
                case .matchRealNotchSize:
                    nonNotchHeight = 32
                case .custom:
                    nonNotchHeight = 32
                }
                NotificationCenter.default.post(
                    name: Notification.Name.notchHeightChanged, object: nil)
            }
            if nonNotchHeightMode == .custom {
                Slider(value: $nonNotchHeight, in: 0...40, step: 1) {
                    HStack {
                        Text("Custom height")
                        Spacer()
                        Text("\(nonNotchHeight, specifier: "%.0f")")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: nonNotchHeight) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch size")
        }
    }

    private var behaviorSection: some View {
        Section {
            Defaults.Toggle(key: .openNotchOnHover) {
                Text("Open notch on hover")
            }
            Defaults.Toggle(key: .enableHaptics) {
                Text("Enable haptic feedback")
            }
            if openNotchOnHover {
                Slider(value: $minimumHoverDuration, in: 0...1, step: 0.1) {
                    HStack {
                        Text("Hover delay")
                        Spacer()
                        Text("\(minimumHoverDuration, specifier: "%.1f")s")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: minimumHoverDuration) {
                    NotificationCenter.default.post(
                        name: Notification.Name.notchHeightChanged, object: nil)
                }
            }
        } header: {
            Text("Notch behavior")
        }
    }

    private var gestureSection: some View {
        Section {
            Defaults.Toggle(key: .enableGestures) {
                Text("Enable gestures")
            }
            .disabled(!openNotchOnHover)
            if enableGestures {
                Defaults.Toggle(key: .closeGestureEnabled) {
                    Text("Close gesture")
                }
                Slider(value: $gestureSensitivity, in: 100...300, step: 100) {
                    HStack {
                        Text("Gesture sensitivity")
                        Spacer()
                        Text(gestureSensitivity == 100 ? "High" : gestureSensitivity == 200 ? "Medium" : "Low")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            HStack {
                Text("Gestures")
                customBadge(text: "Beta")
            }
        } footer: {
            SettingsFooter("Swipe up with two fingers on the notch to close it, and down to open it when Open notch on hover is off.")
        }
    }

    private var batterySection: some View {
        Section {
            Defaults.Toggle(key: .showBatteryIndicator) {
                Text("Show battery indicator")
            }
            Defaults.Toggle(key: .showBatteryPercentage) {
                Text("Show battery percentage")
            }
            .disabled(!showBatteryIndicator)
            Defaults.Toggle(key: .showPowerStatusIcons) {
                Text("Show power status icons")
            }
            .disabled(!showBatteryIndicator)
            Defaults.Toggle(key: .showPowerStatusNotifications) {
                Text("Show power status notifications")
            }
        } header: {
            Text("Battery")
        } footer: {
            SettingsFooter("The indicator sits in the open notch. Power status notifications appear in the closed notch when you plug in or unplug.")
        }
    }
}
