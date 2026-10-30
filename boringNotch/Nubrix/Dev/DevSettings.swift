import AppKit
import Defaults
import SwiftUI

struct DevSettings: View {
    @Default(.devEnabled) var enabled
    @Default(.devPorts) var ports
    @ObservedObject var monitor = DevPortMonitor.shared
    @State private var portText = ""
    @State private var portError = false
    @State private var copied = false

    private static let installCommand = "mkdir -p ~/.local/bin && ln -sf \"$PWD/cli/notchctl\" ~/.local/bin/notchctl"

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .devEnabled) {
                    Text("Enable Dev tab")
                }
            } footer: {
                Text("Shows localhost servers and notifications sent with notchctl.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
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
                Text("Ports are checked every 5 seconds only while the Dev tab or this page is visible.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .disabled(!enabled)

            Section {
                HStack {
                    Text(Self.installCommand)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Self.installCommand, forType: .string)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    }
                }
                Button("Send test notification") {
                    DevNotificationStore.shared.post(
                        DevNotifyRequest(message: "Test notification from Nubrix", title: "notchctl",
                                         style: .success, duration: DevNotifyRequest.defaultDuration)
                    )
                }
                .disabled(!enabled)
            } header: {
                Text("notchctl")
            } footer: {
                Text("Run the command from the Nubrix repository, then use: notchctl notify \"Build done\" --style success")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dev")
        .onAppear {
            portText = Self.format(ports)
            DevPortMonitor.shared.setActive("settings", true)
        }
        .onDisappear {
            DevPortMonitor.shared.setActive("settings", false)
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
