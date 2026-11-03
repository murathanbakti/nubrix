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
    static func isInvisible(_ value: UInt32) -> Bool {
        switch value {
        case 0x00AD, 0x200B...0x200F, 0x2028...0x202E, 0x2060...0x2064, 0x2066...0x2069, 0xFEFF, 0xE0000...0xE007F:
            return true
        default:
            return false
        }
    }

    static func sanitized(_ raw: String?, limit: Int = 128) -> String {
        guard let raw else { return "" }
        let scalars = raw.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F && !isInvisible($0.value) }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespaces).prefix(limit).description
    }

    static func projectName(cwd: String?) -> String {
        let name = sanitized(URL(fileURLWithPath: cwd ?? "").lastPathComponent, limit: 80)
        return name.isEmpty || name == "/" ? "Claude" : name
    }

    static func display(_ raw: String) -> (text: String, hidden: Bool) {
        var out = String.UnicodeScalarView()
        var hidden = false
        for scalar in raw.unicodeScalars {
            let value = scalar.value
            if value == 0x0A || value == 0x09 {
                out.append(scalar)
            } else if value < 0x20 {
                hidden = true
                out.append(Unicode.Scalar(0x2400 + value)!)
            } else if value == 0x7F {
                hidden = true
                out.append(Unicode.Scalar(0x2421)!)
            } else if isInvisible(value) {
                hidden = true
                out.append(contentsOf: String(format: "\u{27E6}U+%04X\u{27E7}", value).unicodeScalars)
            } else {
                out.append(scalar)
            }
        }
        return (String(out), hidden)
    }
}

struct AgentSourceInfo: Equatable {
    static let desktopBundleID = "com.anthropic.claudefordesktop"

    var entrypoint: String = ""
    var appBundleID: String = ""
    var terminal: String = ""
    var hostSessionID: String = ""
    var tty: String = ""
    var focusURL: String = ""

    private static let hostSessionPattern = /^local_[A-Za-z0-9-]{1,64}$/
    private static let ttyPattern = /^ttys[0-9]{1,4}$/
    private static let focusURLPattern = /^warp[a-z]{0,12}:\/\/session\/[0-9a-f]{32}$/

    static func isValidFocusURL(_ value: String) -> Bool {
        value.count <= 64 && value.wholeMatch(of: focusURLPattern) != nil
    }

    init(entrypoint: String? = nil, appBundleID: String? = nil, terminal: String? = nil,
         hostSessionID: String? = nil, tty: String? = nil, focusURL: String? = nil) {
        self.entrypoint = AgentText.sanitized(entrypoint, limit: 48)
        self.appBundleID = AgentText.sanitized(appBundleID, limit: 128)
        self.terminal = AgentText.sanitized(terminal, limit: 48)
        if let hostSessionID, hostSessionID.wholeMatch(of: Self.hostSessionPattern) != nil { self.hostSessionID = hostSessionID }
        if let tty, tty.wholeMatch(of: Self.ttyPattern) != nil { self.tty = tty }
        if let focusURL, Self.isValidFocusURL(focusURL) { self.focusURL = focusURL }
    }

    init(headers: [String: String]) {
        self.init(
            entrypoint: headers["x-nubrix-entrypoint"],
            appBundleID: headers["x-nubrix-app"],
            terminal: headers["x-nubrix-term"],
            hostSessionID: headers["x-nubrix-host-session"],
            tty: headers["x-nubrix-tty"],
            focusURL: headers["x-nubrix-focus-url"]
        )
    }

    var isEmpty: Bool { entrypoint.isEmpty && appBundleID.isEmpty && terminal.isEmpty && hostSessionID.isEmpty && tty.isEmpty && focusURL.isEmpty }

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
        if !other.hostSessionID.isEmpty { hostSessionID = other.hostSessionID }
        if !other.tty.isEmpty { tty = other.tty }
        if !other.focusURL.isEmpty { focusURL = other.focusURL }
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
    var remote: String?
    var contextUsedPercent: Double?
    var contextWindowSize: Int?
    var costUSD: Double?
    var modelName: String?
    var contextWarned = false
    var contextTokens: Int?
    var usageModel: String?
    var sessionTokens = 0
    var estimatedCostUSD: Double?
    var lastUsageMessageID: String?

    var contextWindow: Int? {
        if let contextWindowSize, contextWindowSize > 0 { return contextWindowSize }
        guard let contextTokens else { return nil }
        return AgentContextWindow.infer(model: usageModel, contextTokens: contextTokens)
    }

    var displayModel: String? {
        modelName ?? AgentPricing.friendlyName(usageModel) ?? usageModel
    }

    var displayCost: (value: Double, estimated: Bool)? {
        if let costUSD { return (costUSD, false) }
        if let estimatedCostUSD { return (estimatedCostUSD, true) }
        return nil
    }

    var project: String { AgentText.projectName(cwd: cwd) }

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

    static let permissionLimit = 65_536
    static let keyLength = 512

    static func matchKey(toolName: String, input: [String: Any]?) -> String? {
        guard input != nil else { return nil }
        return String(summary(toolName: toolName, input: input, limit: Int.max).prefix(keyLength))
    }

    static func summary(toolName: String, input: [String: Any]?, limit: Int = AgentToolSummary.limit) -> String {
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
    let toolKey: String?
    var source = AgentSourceInfo()
    var branch: String?
    var remote: String?
    let usage: AgentUsageSample?

    init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty
        else { return nil }
        self.name = name
        self.sessionID = sessionID
        usage = (name == "Stop" || name == "SubagentStop") ? AgentUsageSample(object: object["nubrix_usage"] as? [String: Any]) : nil
        cwd = (object["cwd"] as? String).map { AgentText.sanitized($0, limit: 1024) }
        notificationType = object["notification_type"] as? String
        let tool = object["tool_name"] as? String
        toolName = tool
        toolKey = tool.flatMap { AgentToolSummary.matchKey(toolName: $0, input: object["tool_input"] as? [String: Any]) }
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
        let clean = AgentText.sanitized(line, limit: 4096)
        return clean.count > 160 ? String(clean.prefix(159)) + "…" : clean
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
        cwd = ((workspace?["current_dir"] as? String) ?? (object["cwd"] as? String)).map { AgentText.sanitized($0, limit: 1024) }
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

struct AgentPermissionPreview: Equatable {
    let label: String
    let text: String
    let characters: Int
    let lines: Int
    let truncated: Bool
}

struct AgentPermissionPayload: Equatable {
    static let maxSummary = AgentToolSummary.permissionLimit
    static let maxPreview = 60_000
    static let defaultWait = 12
    static let maxWait = 120

    let id: UUID
    let sessionID: String
    let cwd: String?
    let toolName: String
    let summary: String
    let summaryLines: Int
    let summaryTruncated: Bool
    let preview: AgentPermissionPreview?
    let note: String?
    let extraInput: String?
    let risks: [String]
    let matchKey: String?
    let waitSeconds: Int
    var source = AgentSourceInfo()

    init(id: UUID = UUID(), sessionID: String, cwd: String? = nil, toolName: String, summary: String,
         summaryTruncated: Bool = false, preview: AgentPermissionPreview? = nil, note: String? = nil,
         extraInput: String? = nil, risks: [String] = [], matchKey: String? = nil, waitSeconds: Int = AgentPermissionPayload.defaultWait,
         source: AgentSourceInfo = AgentSourceInfo()) {
        self.id = id
        self.sessionID = sessionID
        self.cwd = cwd
        self.toolName = toolName
        self.summary = summary
        summaryLines = summary.isEmpty ? 0 : summary.split(separator: "\n", omittingEmptySubsequences: false).count
        self.summaryTruncated = summaryTruncated
        self.preview = preview
        self.note = note
        self.extraInput = extraInput
        self.risks = risks
        self.matchKey = matchKey
        self.waitSeconds = waitSeconds
        self.source = source
    }

    static let interactiveTools: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    init?(json: Data, waitHeader: String?, source: AgentSourceInfo, id: UUID = UUID()) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty,
              let toolName = object["tool_name"] as? String, !toolName.isEmpty,
              !Self.interactiveTools.contains(toolName)
        else { return nil }
        let input = object["tool_input"] as? [String: Any]
        let cwd = object["cwd"] as? String

        let fullSummary = AgentToolSummary.summary(toolName: toolName, input: input, limit: Int.max)
        let truncated = fullSummary.count > Self.maxSummary
        let rawSummary = truncated ? String(fullSummary.prefix(Self.maxSummary)) : fullSummary
        let shown = AgentText.display(rawSummary)
        let preview = AgentPermissionPreviewBuilder.build(toolName: toolName, input: input, limit: Self.maxPreview)
        let description = AgentText.display(AgentText.sanitized(input?["description"] as? String, limit: 200))

        var extraText: String?
        var extraHidden = false
        if toolName == "Bash" || toolName == "PowerShell" {
            let extra = AgentPermissionRisk.extraShellInput(input)
            if !extra.isEmpty {
                let compact = AgentToolSummary.compact(extra)
                let clipped = compact.count > 2000 ? String(compact.prefix(2000)) + "…" : compact
                let display = AgentText.display(clipped)
                extraText = display.text
                extraHidden = display.hidden
            }
        }

        var risks = AgentPermissionRisk.assess(toolName: toolName, input: input, cwd: cwd, summary: fullSummary)
        func add(_ reason: String) { if !risks.contains(reason) { risks.append(reason) } }
        if truncated { add("Input truncated, not fully shown") }
        if preview?.truncated == true { add("Content preview truncated") }
        if shown.hidden || preview?.hidden == true || description.hidden || extraHidden { add("Hidden or control characters") }

        self.init(
            id: id,
            sessionID: sessionID,
            cwd: cwd,
            toolName: AgentText.sanitized(toolName, limit: 80),
            summary: shown.text,
            summaryTruncated: truncated,
            preview: preview?.preview,
            note: description.text.isEmpty ? nil : description.text,
            extraInput: extraText,
            risks: risks,
            matchKey: AgentToolSummary.matchKey(toolName: toolName, input: input),
            waitSeconds: min(Self.maxWait, max(3, waitHeader.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? Self.defaultWait)),
            source: source
        )
    }
}

enum AgentPermissionPreviewBuilder {
    struct Built {
        let preview: AgentPermissionPreview
        let hidden: Bool
        var truncated: Bool { preview.truncated }
    }

    static func build(toolName: String, input: [String: Any]?, limit: Int) -> Built? {
        guard let input else { return nil }
        let label: String
        let raw: String
        switch toolName {
        case "Write":
            guard let content = input["content"] as? String else { return nil }
            label = "Content to write"
            raw = content
        case "Edit":
            guard let change = diff(old: input["old_string"] as? String, new: input["new_string"] as? String) else { return nil }
            label = AgentPermissionRisk.isTrue(input["replace_all"]) ? "Change · replace all occurrences" : "Change"
            raw = change
        case "MultiEdit":
            guard let edits = input["edits"] as? [[String: Any]], !edits.isEmpty else { return nil }
            label = edits.contains(where: { AgentPermissionRisk.isTrue($0["replace_all"]) })
                ? "Changes · replace all occurrences" : "Changes"
            raw = edits.compactMap { diff(old: $0["old_string"] as? String, new: $0["new_string"] as? String) }
                .joined(separator: "\n@@\n")
        case "NotebookEdit":
            guard let source = input["new_source"] as? String else { return nil }
            label = "New cell source"
            raw = source
        default:
            return nil
        }
        let characters = raw.count
        let truncated = characters > limit
        let clipped = truncated ? String(raw.prefix(limit)) : raw
        let shown = AgentText.display(clipped)
        let lines = raw.isEmpty ? 0 : raw.split(separator: "\n", omittingEmptySubsequences: false).count
        return Built(
            preview: AgentPermissionPreview(label: label, text: shown.text, characters: characters, lines: lines, truncated: truncated),
            hidden: shown.hidden
        )
    }

    private static func diff(old: String?, new: String?) -> String? {
        guard old != nil || new != nil else { return nil }
        func prefixed(_ text: String?, _ mark: String) -> [String] {
            guard let text, !text.isEmpty else { return [] }
            return text.split(separator: "\n", omittingEmptySubsequences: false).map { "\(mark) \($0)" }
        }
        return (prefixed(old, "-") + prefixed(new, "+")).joined(separator: "\n")
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

    var decision: String {
        switch self {
        case .allow: return "allow"
        case .deny: return "deny"
        case .none: return "none"
        }
    }

    func body(proof: String) -> String {
        switch self {
        case .allow: return "{\"decision\":\"allow\",\"proof\":\"\(proof)\"}"
        case .deny: return "{\"decision\":\"deny\",\"message\":\"Denied from the Nubrix notch\",\"proof\":\"\(proof)\"}"
        case .none: return "{\"decision\":\"none\",\"proof\":\"\(proof)\"}"
        }
    }
}
