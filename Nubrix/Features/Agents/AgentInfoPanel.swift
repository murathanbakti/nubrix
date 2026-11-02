import AppKit
import SwiftUI

struct AgentInfoSnapshot {
    var lastHookEventAt: Date?
    var lastStatusAt: Date?
    var approvalsEnabled: Bool
    var sealedScripts: Int
    var sealedTotal: Int
    var serverPort: UInt16?
}

struct AgentInfoProblem: Identifiable, Equatable {
    let id: String
    let message: String
}

enum AgentInfoModel {
    static let sealedNames = ["nubrix-hook", "nubrix-permission", "nubrix-statusline", "notchctl"]
    static let hooksFreshness: TimeInterval = 10 * 60
    static let statusLineNote = "Status line not available in the desktop app (terminal only) \u{2014} usage comes from transcripts instead."

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }

    static func problems(_ snapshot: AgentInfoSnapshot, now: Date) -> [AgentInfoProblem] {
        var result: [AgentInfoProblem] = []

        if snapshot.serverPort == nil {
            result.append(AgentInfoProblem(id: "server", message: "Local server is not running \u{2014} restart Nubrix"))
        }

        if snapshot.sealedScripts == 0 {
            result.append(AgentInfoProblem(id: "sealed", message: "Hook scripts not installed \u{2014} run install-hooks.sh (see README)"))
        } else if snapshot.sealedScripts < snapshot.sealedTotal {
            result.append(AgentInfoProblem(id: "sealed", message: "\(snapshot.sealedScripts) of \(snapshot.sealedTotal) hook scripts installed \u{2014} run install-hooks.sh (see README)"))
        }

        if let date = snapshot.lastHookEventAt {
            if now.timeIntervalSince(date) > hooksFreshness {
                result.append(AgentInfoProblem(id: "hooks", message: "No hook events for \(ago(date, now: now)) \u{2014} if Claude is running, restart it"))
            }
        } else {
            result.append(AgentInfoProblem(id: "hooks", message: "Hooks not seen yet \u{2014} run install-hooks.sh (see README) and restart Claude"))
        }
        return result
    }

    static func showsStatusLineNote(_ snapshot: AgentInfoSnapshot) -> Bool {
        snapshot.lastStatusAt == nil
    }

    static func sealedCount(in directory: URL) -> Int {
        sealedNames.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }.count
    }

    static func setupSnippet(binDirectory: String) -> String {
        func quote(_ path: String) -> String {
            path.contains(where: \.isWhitespace) ? "\\\"\(path)\\\"" : path
        }
        let hook = quote(binDirectory + "/nubrix-hook")
        let permission = quote(binDirectory + "/nubrix-permission")
        let statusLine = quote(binDirectory + "/nubrix-statusline")
        let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                      "PermissionRequest", "PermissionDenied", "Notification", "Stop", "StopFailure", "SessionEnd"]
        var lines = ["{", "  \"hooks\": {"]
        for (index, event) in events.enumerated() {
            let comma = index == events.count - 1 ? "" : ","
            if event == "PermissionRequest" {
                lines.append("    \"PermissionRequest\": [")
                lines.append("      { \"hooks\": [")
                lines.append("        { \"type\": \"command\", \"command\": \"\(hook)\", \"async\": true, \"timeout\": 5 },")
                lines.append("        { \"type\": \"command\", \"command\": \"\(permission)\", \"timeout\": 125 }")
                lines.append("      ] }")
                lines.append("    ]\(comma)")
            } else {
                lines.append("    \"\(event)\": [ { \"hooks\": [ { \"type\": \"command\", \"command\": \"\(hook)\", \"async\": true, \"timeout\": 5 } ] } ]\(comma)")
            }
        }
        lines.append("  },")
        lines.append("  \"statusLine\": { \"type\": \"command\", \"command\": \"\(statusLine)\" },")
        lines.append("  \"permissions\": {")
        lines.append("    \"deny\": [\"Edit(~/.config/nubrix/**)\", \"Write(~/.config/nubrix/**)\", \"Edit(~/.config/nubrix-run/**)\", \"Write(~/.config/nubrix-run/**)\", \"Read(~/.config/nubrix-run/**)\"]")
        lines.append("  }")
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}

struct AgentInfoPanel: View {
    let snapshot: AgentInfoSnapshot
    let now: Date
    var onCopy: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    @State private var copied = false

    var body: some View {
        let problems = AgentInfoModel.problems(snapshot, now: now)
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                if problems.isEmpty {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.green)
                        Text("All connected")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                } else {
                    ForEach(problems) { problem in
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                            Text(problem.message)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(white: 0.85))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
                if AgentInfoModel.showsStatusLineNote(snapshot) {
                    Text(AgentInfoModel.statusLineNote)
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

            HStack(spacing: 8) {
                Button(action: onOpenSettings) {
                    HStack(spacing: 4) {
                        Text("Approvals in the notch: \(snapshot.approvalsEnabled ? "On" : "Off")")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(Color(white: 0.8))
                }
                .buttonStyle(.plain)
                .help("Open Settings, Notifications")
                Spacer(minLength: 8)
                Button {
                    onCopy()
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text(copied ? "Copied" : "Copy setup snippet")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(copied ? Color.green : Color(white: 0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Copies the settings.json snippet for ~/.claude/settings.json")
            }
            .padding(.horizontal, 4)

            if let port = snapshot.serverPort {
                Text(verbatim: "Local server 127.0.0.1:\(port)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
