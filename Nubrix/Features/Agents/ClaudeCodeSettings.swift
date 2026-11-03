import Defaults
import SwiftUI

struct ClaudeCodeSettings: View {
    @Default(.claudeEnabled) var enabled
    @Default(.claudePlanUsageEnabled) var planUsageEnabled

    static let installCommand = installCommand(bundleURL: Bundle.main.bundleURL)

    static func installCommand(bundleURL: URL) -> String {
        let script = bundleURL
            .appendingPathComponent("Contents/Resources/nubrix-hooks/scripts/install-hooks.sh")
            .path
        return "bash " + shellQuoted(script)
    }

    static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")
        if !value.isEmpty, value.unicodeScalars.allSatisfy(safe.contains) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .claudeEnabled) {
                    Text("Enable Claude Code integration")
                }
            } footer: {
                SettingsFooter(
                    "Shows your Claude Code sessions in the notch and lets you approve permissions there. Nothing is ever approved automatically.",
                    link: ("How it works", SettingsLinks.claudeCodeGuide)
                )
            }

            Group {
                Section {
                    Defaults.Toggle(key: .claudeNotchApprovals) {
                        Text("Approve permissions from the notch")
                    }
                    Defaults.Toggle(key: .claudeOpenSession) {
                        Text("Open the session when you click it")
                    }
                } header: {
                    Text("Sessions")
                } footer: {
                    SettingsFooter("Approvals need the nubrix-permission hook. Opening a session in Terminal, iTerm or Ghostty asks for Automation the first time.")
                }

                Section {
                    Defaults.Toggle(key: .homeShowClaudeUsage) {
                        Text("Show 5-hour and weekly usage on the Home tab")
                    }
                    Defaults.Toggle(key: .claudePlanUsageEnabled) {
                        Text("Show official plan usage")
                    }
                } header: {
                    Text("Usage")
                } footer: {
                    SettingsFooter("Plan usage runs claude /usage in the background every 5 to 30 minutes. It costs no tokens and keeps only percentages and reset times.")
                }
            }
            .disabled(!enabled)

            Section {
                CopyCommandRow(command: Self.installCommand)
            } header: {
                Text("Hooks")
            } footer: {
                SettingsFooter("Run this in a terminal, then merge the printed snippet into ~/.claude/settings.json. Run it again after each Nubrix update.")
            }
        }
        .settingsPage(.claudeCode)
        .onChange(of: planUsageEnabled) { _, _ in ClaudePlanUsageStore.shared.settingChanged() }
    }
}
