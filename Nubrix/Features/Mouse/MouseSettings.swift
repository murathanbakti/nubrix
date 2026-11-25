import Defaults
import SwiftUI

struct MouseSettings: View {
    @ObservedObject private var controller = MouseScrollController.shared
    @Default(.mouseScrollMode) private var mode
    @Default(.mouseScrollReverseHorizontal) private var reverseHorizontal

    var body: some View {
        Form {
            Section {
                Picker("Reverse mouse scrolling", selection: $mode) {
                    ForEach(MouseScrollMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                if mode != .off && !controller.accessibilityGranted {
                    HStack {
                        Label("Needs Accessibility", systemImage: "lock.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant…") {
                            Task { await controller.requestAccessibility() }
                        }
                    }
                }
            } footer: {
                SettingsFooter("Flips the scroll wheel of a USB or Bluetooth mouse. Your trackpad and Magic Mouse keep the macOS direction. Accessibility is used only to flip scroll events; nothing is recorded or sent.")
            }

            Section {
                LabeledContent("Trackpad", value: controller.trackpadDirection)
                LabeledContent("Mouse wheel", value: controller.mouseWheelDirection)
                LabeledContent("State", value: controller.status.title)
            } header: {
                Text("Status")
            } footer: {
                SettingsFooter(
                    "Natural scrolling itself is set in System Settings.",
                    link: ("Open Mouse settings", URL(string: "x-apple.systempreferences:com.apple.Mouse-Settings.extension")!)
                )
            }

            Section {
                if controller.mice.isEmpty {
                    Text("None connected").foregroundStyle(.secondary)
                }
                ForEach(controller.mice) { mouse in
                    Toggle(isOn: Binding(
                        get: { !controller.ignoredDevices.contains(mouse.key) },
                        set: { controller.setCounted(mouse, $0) }
                    )) {
                        VStack(alignment: .leading) {
                            Text(mouse.name)
                            if let transport = mouse.transport {
                                Text(transport).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Detected mice")
            } footer: {
                SettingsFooter("\"When a mouse is connected\" turns on while a switched-on device is plugged in. Some keyboards also report a mouse; switch those off.")
            }

            Section {
                Toggle("Reverse horizontal scrolling too", isOn: $reverseHorizontal)
                    .disabled(mode == .off)
            } header: {
                Text("Options")
            } footer: {
                SettingsFooter("Applies to the tilt or side wheel of a mouse.")
            }
        }
        .settingsPage(.mouse)
        .task { await controller.evaluate() }
        .onAppear {
            controller.refreshDevices()
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onChange(of: mode) {
            Task { await controller.modeDidChange(to: mode) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidShow)) { _ in
            controller.refreshDevices()
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
            Task { await controller.evaluate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { _ in
            Task { await controller.evaluate() }
        }
    }
}
