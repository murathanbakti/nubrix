import AppKit
import SwiftUI

struct AgentInfoSnapshot {
    var lastHookEventAt: Date?
    var lastStatusAt: Date?
    var approvalsEnabled: Bool
    var lastPermissionRequestAt: Date?
    var sealedScripts: Int
    var sealedTotal: Int
    var serverPort: UInt16?
}

enum AgentInfoLevel {
    case ok
    case warn
    case none

    var color: Color {
        switch self {
        case .ok: return .green
        case .warn: return .orange
        case .none: return Color(white: 0.4)
        }
    }
}

struct AgentInfoCheck: Identifiable {
    let id: String
    let title: String
    let detail: String
    let level: AgentInfoLevel
}

enum AgentInfoModel {
    static let sealedNames = ["nubrix-hook", "nubrix-permission", "nubrix-statusline", "notchctl"]

    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    static func checks(_ snapshot: AgentInfoSnapshot, now: Date) -> [AgentInfoCheck] {
        var result: [AgentInfoCheck] = []

        if let date = snapshot.lastHookEventAt {
            result.append(AgentInfoCheck(id: "hooks", title: "Event hooks", detail: "last event \(ago(date, now: now))", level: .ok))
        } else {
            result.append(AgentInfoCheck(id: "hooks", title: "Event hooks", detail: "No events yet", level: .none))
        }

        if let date = snapshot.lastStatusAt {
            result.append(AgentInfoCheck(id: "status", title: "Status line", detail: "last update \(ago(date, now: now))", level: .ok))
        } else {
            result.append(AgentInfoCheck(id: "status", title: "Status line", detail: "Not configured", level: .none))
        }

        if !snapshot.approvalsEnabled {
            result.append(AgentInfoCheck(id: "approvals", title: "Notch approvals", detail: "Off", level: .none))
        } else if let date = snapshot.lastPermissionRequestAt {
            result.append(AgentInfoCheck(id: "approvals", title: "Notch approvals", detail: "On · last request \(ago(date, now: now))", level: .ok))
        } else {
            result.append(AgentInfoCheck(id: "approvals", title: "Notch approvals", detail: "On · no request received yet", level: .warn))
        }

        if snapshot.sealedScripts >= snapshot.sealedTotal {
            result.append(AgentInfoCheck(id: "sealed", title: "Sealed hooks", detail: "\(snapshot.sealedScripts) of \(snapshot.sealedTotal) scripts installed", level: .ok))
        } else if snapshot.sealedScripts > 0 {
            result.append(AgentInfoCheck(id: "sealed", title: "Sealed hooks", detail: "\(snapshot.sealedScripts) of \(snapshot.sealedTotal) scripts found", level: .warn))
        } else {
            result.append(AgentInfoCheck(id: "sealed", title: "Sealed hooks", detail: "Not installed", level: .none))
        }

        if let port = snapshot.serverPort {
            result.append(AgentInfoCheck(id: "server", title: "Local server", detail: "127.0.0.1:\(port) · running", level: .ok))
        } else {
            result.append(AgentInfoCheck(id: "server", title: "Local server", detail: "Not running", level: .warn))
        }
        return result
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
        lines.append("    \"deny\": [\"Edit(~/.config/nubrix/**)\", \"Write(~/.config/nubrix/**)\"]")
        lines.append("  }")
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}

struct AgentInfoPanel: View {
    let snapshot: AgentInfoSnapshot
    let now: Date
    var onCopy: () -> Void = {}
    @State private var copied = false

    private static let features: [(icon: String, title: String, detail: String)] = [
        ("circle.dotted", "Session status", "Working, needs you, done or failed, live in the notch."),
        ("terminal", "Source & branch", "A Desktop, Terminal or VS Code chip per session; click a row to jump there."),
        ("gauge.with.dots.needle.33percent", "Context & usage", "The status line feeds context %, cost and the 5h / 7d limits."),
        ("checkmark.shield", "Approve from the notch", "Allow or Deny with the full command; risky ones need a second click. Answers are signed, and Claude's own dialog is the fallback."),
        ("bell.badge", "notchctl", "Send notifications to the notch from your own scripts.")
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                section("Status")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 4) {
                    ForEach(AgentInfoModel.checks(snapshot, now: now)) { check in
                        statusRow(check)
                    }
                }
                section("What it does")
                VStack(spacing: 4) {
                    ForEach(Self.features, id: \.title) { feature in
                        featureRow(feature.icon, feature.title, feature.detail)
                    }
                }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
        }
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color(white: 0.5))
            .padding(.horizontal, 4)
    }

    private func statusRow(_ check: AgentInfoCheck) -> some View {
        HStack(spacing: 7) {
            Circle().fill(check.level.color).frame(width: 6, height: 6)
            Text(check.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
            Text(check.detail)
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func featureRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AgentSessionState.working.tint)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 130, alignment: .leading)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}
