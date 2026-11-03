import AppKit
import Defaults
import SwiftUI

struct DevSettings: View {
    @Default(.devEnabled) var enabled
    @Default(.devPorts) var ports
    @ObservedObject var monitor = DevPortMonitor.shared
    @State private var portText = ""
    @State private var portError = false

    private static let installCommand = "mkdir -p ~/.local/bin && ln -sf ~/.config/nubrix/bin/notchctl ~/.local/bin/notchctl"

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .devEnabled) {
                    Text("Enable Dev tab")
                }
            } footer: {
                SettingsFooter("Shows localhost servers and notifications sent with notchctl.")
            }

            Section {
                TextField("Ports", text: $portText)
                    .onSubmit(applyPorts)
                    .onChange(of: portText) { _, _ in portError = false }
                HStack {
                    Button("Apply", action: applyPorts)
                    Button("Restore defaults") {
                        ports = DevPortCatalog.defaultPorts
                        portText = Self.format(ports)
                        portError = false
                        monitor.refresh()
                    }
                }
                if portError {
                    Text("Enter comma-separated ports between 1 and 65535.")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                if monitor.servers.isEmpty {
                    Text("No listening ports found.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Listening: " + monitor.servers.map { "\($0.port) \($0.label)" }.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            } header: {
                Text("Watched ports")
            } footer: {
                SettingsFooter("Ports are checked every 15 seconds, only while the Dev tab or this page is visible.")
            }
            .disabled(!enabled)

            Section {
                CopyCommandRow(command: Self.installCommand)
                Button("Send test notification") {
                    DevNotificationStore.shared.post(
                        DevNotifyRequest(message: "Test notification from Nubrix", title: "notchctl",
                                         style: .success, duration: DevNotifyRequest.defaultDuration)
                    )
                }
            } header: {
                Text("notchctl")
            } footer: {
                SettingsFooter("Install the hooks first (see Claude Code), then run this command and use: notchctl notify \"Build done\" --style success")
            }
            .disabled(!enabled)
        }
        .settingsPage(.dev)
        .onAppear {
            portText = Self.format(ports)
            DevPortMonitor.shared.setActive("settings", true)
        }
        .onDisappear {
            DevPortMonitor.shared.setActive("settings", false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidShow)) { _ in
            DevPortMonitor.shared.setActive("settings", true)
        }
    }

    private func applyPorts() {
        guard let parsed = DevPortCatalog.parse(portText) else {
            portError = true
            return
        }
        ports = parsed
        portText = Self.format(parsed)
        portError = false
        monitor.refresh()
    }

    private static func format(_ ports: [Int]) -> String {
        ports.map(String.init).joined(separator: ", ")
    }
}
