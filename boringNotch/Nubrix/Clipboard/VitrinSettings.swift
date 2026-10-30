import AppKit
import Defaults
import SwiftUI

struct VitrinSettings: View {
    @Default(.vitrinRetentionDays) var retentionDays
    @Default(.vitrinExcludedApps) var excludedApps
    @ObservedObject var store = ClipStore.shared
    @State private var newBundleID = ""
    @State private var confirmClear = false

    private static let retentionOptions: [(label: String, days: Int)] = [
        ("1 day", 1), ("7 days", 7), ("30 days", 30), ("90 days", 90), ("Forever", 0)
    ]

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .vitrinEnabled) {
                    Text("Enable Vitrin")
                }
            } footer: {
                Text("Keeps what you copy on this Mac and shows it in the notch and in the showcase panel.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section("Capture") {
                Defaults.Toggle(key: .vitrinCaptureImages) { Text("Images") }
                Defaults.Toggle(key: .vitrinCaptureText) { Text("Text") }
                Defaults.Toggle(key: .vitrinCaptureLinks) { Text("Links") }
            }

            Section {
                Picker("Keep history for", selection: $retentionDays) {
                    ForEach(Self.retentionOptions, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
                Button("Clear history\u{2026}", role: .destructive) {
                    confirmClear = true
                }
                .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
                    Button("Clear history", role: .destructive) { store.clearHistory() }
                } message: {
                    Text("Pinned items are kept.")
                }
            } header: {
                Text("History")
            } footer: {
                Text("Pinned items never expire. Text that looks like a password, key or token is never stored.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                ForEach(excludedApps, id: \.self) { id in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Self.appName(for: id) ?? id)
                            if Self.appName(for: id) != nil {
                                Text(id).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            excludedApps.removeAll { $0 == id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    TextField("Bundle identifier", text: $newBundleID, prompt: Text("com.example.app"))
                        .onSubmit(addBundleID)
                    Button("Add", action: addBundleID)
                        .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Restore default list") {
                    excludedApps = VitrinDefaultsValues.excludedApps
                }
            } header: {
                Text("Excluded apps")
            } footer: {
                Text("Nothing copied while one of these apps is frontmost is stored.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .accentColor(.effectiveAccent)
        .navigationTitle("Vitrin")
    }

    private func addBundleID() {
        let id = newBundleID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !excludedApps.contains(id) else { return }
        excludedApps.append(id)
        newBundleID = ""
    }

    private static func appName(for bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
