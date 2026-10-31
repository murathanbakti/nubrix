import Foundation
import SwiftUI

enum AgentSessionState: Int, Comparable {
    case needsAttention
    case working
    case failed
    case done
    case idle

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .needsAttention: return "Needs you"
        case .working: return "Working"
        case .failed: return "Failed"
        case .done: return "Done"
        case .idle: return "Idle"
        }
    }

    var tint: Color {
        switch self {
        case .needsAttention: return .orange
        case .working: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .failed: return .red
        case .done: return .green
        case .idle: return .gray
        }
    }
}

enum AgentText {
    static func sanitized(_ raw: String?, limit: Int = 128) -> String {
        guard let raw else { return "" }
        let scalars = raw.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces).prefix(limit).description
    }
}

struct AgentSourceInfo: Equatable {
    static let desktopBundleID = "com.anthropic.claudefordesktop"

    var entrypoint: String = ""
    var appBundleID: String = ""
    var terminal: String = ""

    init(entrypoint: String? = nil, appBundleID: String? = nil, terminal: String? = nil) {
        self.entrypoint = AgentText.sanitized(entrypoint, limit: 48)
        self.appBundleID = AgentText.sanitized(appBundleID, limit: 128)
        self.terminal = AgentText.sanitized(terminal, limit: 48)
    }

    init(headers: [String: String]) {
        self.init(
            entrypoint: headers["x-nubrix-entrypoint"],
            appBundleID: headers["x-nubrix-app"],
            terminal: headers["x-nubrix-term"]
        )
    }

    var isEmpty: Bool { entrypoint.isEmpty && appBundleID.isEmpty && terminal.isEmpty }

    var activationBundleID: String? {
        if !appBundleID.isEmpty { return appBundleID }
        return entrypoint == "claude-desktop" ? Self.desktopBundleID : nil
    }

    private static let knownApps: [String: String] = [
        "com.anthropic.claudefordesktop": "Desktop",
        "com.googlecode.iterm2": "iTerm",
        "com.apple.Terminal": "Terminal",
        "com.mitchellh.ghostty": "Ghostty",
        "dev.warp.Warp-Stable": "Warp",
        "dev.warp.Warp": "Warp",
        "com.microsoft.VSCode": "VS Code",
        "com.microsoft.VSCodeInsiders": "VS Code",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
        "net.kovidgoyal.kitty": "kitty",
        "org.alacritty": "Alacritty",
        "com.github.wez.wezterm": "WezTerm",
        "co.zeit.hyper": "Hyper",
        "com.zed.Zed": "Zed",
        "dev.zed.Zed": "Zed",
        "com.jetbrains.intellij": "JetBrains",
        "com.googlecode.iterm2.beta": "iTerm",
    ]

    private static let editors: Set<String> = ["VS Code", "Cursor", "Windsurf", "Zed", "JetBrains"]

    private static let termPrograms: [String: String] = [
        "iTerm.app": "iTerm",
        "Apple_Terminal": "Terminal",
        "ghostty": "Ghostty",
        "WarpTerminal": "Warp",
        "vscode": "VS Code",
        "WezTerm": "WezTerm",
        "kitty": "kitty",
        "Hyper": "Hyper",
        "alacritty": "Alacritty",
    ]

    private var appName: String? {
        if let name = Self.knownApps[appBundleID] { return name }
        if appBundleID.hasPrefix("com.jetbrains.") { return "JetBrains" }
        if let name = Self.termPrograms[terminal] { return name }
        return nil
    }

    var label: String? {
        if isEmpty { return nil }
        let name = appName
        if entrypoint == "claude-desktop" { return "Desktop" }
        if entrypoint == "claude-vscode" { return name.flatMap { Self.editors.contains($0) ? $0 : nil } ?? "VS Code" }
        if let name, Self.editors.contains(name) { return name }
        if let name, name == "Terminal" { return "Terminal" }
        if let name, name != "Desktop" { return "Terminal · \(name)" }
        if entrypoint == "cli" || !terminal.isEmpty { return "Terminal" }
        return entrypoint.isEmpty ? nil : entrypoint
    }

    mutating func merge(_ other: AgentSourceInfo) {
        if !other.entrypoint.isEmpty { entrypoint = other.entrypoint }
        if !other.appBundleID.isEmpty { appBundleID = other.appBundleID }
        if !other.terminal.isEmpty { terminal = other.terminal }
    }
}

struct AgentRateLimits: Equatable {
    var fiveHourPercent: Double?
    var fiveHourResetsAt: Date?
    var sevenDayPercent: Double?
    var sevenDayResetsAt: Date?

    var isEmpty: Bool { fiveHourPercent == nil && sevenDayPercent == nil }

    func current(at now: Date = Date()) -> AgentRateLimits? {
        var copy = self
        if let reset = copy.fiveHourResetsAt, reset <= now { copy.fiveHourPercent = nil; copy.fiveHourResetsAt = nil }
        if let reset = copy.sevenDayResetsAt, reset <= now { copy.sevenDayPercent = nil; copy.sevenDayResetsAt = nil }
        return copy.isEmpty ? nil : copy
    }

    init(fiveHourPercent: Double? = nil, fiveHourResetsAt: Date? = nil, sevenDayPercent: Double? = nil, sevenDayResetsAt: Date? = nil) {
        self.fiveHourPercent = fiveHourPercent
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayPercent = sevenDayPercent
        self.sevenDayResetsAt = sevenDayResetsAt
    }

    init?(object: [String: Any]?) {
        guard let object else { return nil }
        func window(_ key: String) -> (Double?, Date?) {
            guard let dict = object[key] as? [String: Any] else { return (nil, nil) }
            let percent = (dict["used_percentage"] as? NSNumber)?.doubleValue
            let reset = (dict["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return (percent.map { max(0, $0) }, reset)
        }
        let five = window("five_hour")
        let seven = window("seven_day")
        self.init(fiveHourPercent: five.0, fiveHourResetsAt: five.1, sevenDayPercent: seven.0, sevenDayResetsAt: seven.1)
        if isEmpty { return nil }
    }
}

struct AgentSession: Identifiable, Equatable {
    let id: String
    var cwd: String
    var state: AgentSessionState
    var detail: String?
    var startedAt: Date
    var updatedAt: Date
    var source = AgentSourceInfo()
    var branch: String?
    var contextUsedPercent: Double?
    var contextWindowSize: Int?
    var costUSD: Double?
    var modelName: String?
    var contextWarned = false

    var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty || name == "/" ? "Claude" : name
    }

    var projectWithBranch: String {
        guard let branch, !branch.isEmpty else { return project }
        return "\(project) · \(branch)"
    }
}

struct AgentBanner: Equatable {
    let sessionID: String
    let project: String
    let state: AgentSessionState
    var note: String? = nil
}

enum AgentToolSummary {
    static let limit = 4000

    static func summary(toolName: String, input: [String: Any]?) -> String {
        guard let input else { return "" }
        func string(_ key: String) -> String? { (input[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let text: String
        switch toolName {
        case "Bash", "PowerShell":
            text = string("command") ?? compact(input)
        case "Write", "Edit", "MultiEdit", "Read", "NotebookEdit":
            text = string("file_path") ?? string("notebook_path") ?? compact(input)
        case "WebFetch":
            text = string("url") ?? compact(input)
        case "WebSearch":
            text = string("query") ?? compact(input)
        case "Glob", "Grep":
            let pattern = string("pattern") ?? ""
            text = [pattern, string("path")].compactMap { $0 }.joined(separator: "  in ")
        default:
            text = compact(input)
        }
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    static func compact(_ input: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

struct AgentHookEvent {
    let name: String
    let sessionID: String
    let cwd: String?
    let notificationType: String?
    let detail: String?
    let toolName: String?
    let toolSummary: String?
    var source = AgentSourceInfo()
    var branch: String?

    init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { return nil }
        self.name = name
        self.sessionID = sessionID
        cwd = object["cwd"] as? String
        notificationType = object["notification_type"] as? String
        let tool = object["tool_name"] as? String
        toolName = tool
        toolSummary = tool.map { AgentToolSummary.summary(toolName: $0, input: object["tool_input"] as? [String: Any]) }
        let raw = (object["last_assistant_message"] as? String)
            ?? (object["message"] as? String)
            ?? (object["prompt"] as? String)
            ?? tool
        detail = raw.map(Self.summarize)
    }

    private static func summarize(_ text: String) -> String {
        let line = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return line.count > 160 ? String(line.prefix(159)) + "…" : line
    }
}

struct AgentStatusUpdate: Equatable {
    let sessionID: String
    let cwd: String?
    let modelName: String?
    let contextUsedPercent: Double?
    let contextWindowSize: Int?
    let costUSD: Double?
    let rateLimits: AgentRateLimits?
    var source = AgentSourceInfo()
    var branch: String?

    init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { return nil }
        self.sessionID = sessionID
        let workspace = object["workspace"] as? [String: Any]
        cwd = (workspace?["current_dir"] as? String) ?? (object["cwd"] as? String)
        let model = object["model"] as? [String: Any]
        let name = AgentText.sanitized((model?["display_name"] as? String) ?? (model?["id"] as? String), limit: 40)
        modelName = name.isEmpty ? nil : name
        let context = object["context_window"] as? [String: Any]
        contextUsedPercent = (context?["used_percentage"] as? NSNumber).map { min(100, max(0, $0.doubleValue)) }
        contextWindowSize = (context?["context_window_size"] as? NSNumber).map(\.intValue)
        costUSD = ((object["cost"] as? [String: Any])?["total_cost_usd"] as? NSNumber).map { max(0, $0.doubleValue) }
        rateLimits = AgentRateLimits(object: object["rate_limits"] as? [String: Any])
    }
}

struct AgentPermissionPayload: Equatable {
    static let maxSummary = AgentToolSummary.limit
    static let defaultWait = 25
    static let maxWait = 120

    let id: UUID
    let sessionID: String
    let cwd: String?
    let toolName: String
    let summary: String
    let note: String?
    let risks: [String]
    let waitSeconds: Int
    var source = AgentSourceInfo()

    init?(json: Data, waitHeader: String?, source: AgentSourceInfo, id: UUID = UUID()) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty,
              let toolName = object["tool_name"] as? String, !toolName.isEmpty
        else { return nil }
        let input = object["tool_input"] as? [String: Any]
        let cwd = object["cwd"] as? String
        self.id = id
        self.sessionID = sessionID
        self.cwd = cwd
        self.toolName = AgentText.sanitized(toolName, limit: 80)
        summary = AgentToolSummary.summary(toolName: toolName, input: input)
        let description = AgentText.sanitized(input?["description"] as? String, limit: 200)
        note = description.isEmpty ? nil : description
        risks = AgentPermissionRisk.assess(toolName: toolName, input: input, cwd: cwd)
        let requested = waitHeader.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? Self.defaultWait
        waitSeconds = min(Self.maxWait, max(3, requested))
        self.source = source
    }
}

struct AgentPermissionPrompt: Identifiable, Equatable {
    let payload: AgentPermissionPayload
    let createdAt: Date

    var id: UUID { payload.id }
    var requiresConfirmation: Bool { !payload.risks.isEmpty }
}

enum AgentPermissionAnswer: Equatable {
    case allow
    case deny
    case none

    var body: String {
        switch self {
        case .allow: return "{\"decision\":\"allow\"}"
        case .deny: return "{\"decision\":\"deny\",\"message\":\"Denied from the Nubrix notch\"}"
        case .none: return "{\"decision\":\"none\"}"
        }
    }
}
