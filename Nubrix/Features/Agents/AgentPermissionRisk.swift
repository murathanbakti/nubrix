import Foundation

enum AgentPermissionRisk {
    private struct Rule {
        let reason: String
        let regex: NSRegularExpression

        init(_ reason: String, _ pattern: String) {
            self.reason = reason
            regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }

        func matches(_ text: String) -> Bool {
            regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
    }

    private static let commandRules: [Rule] = [
        Rule("Recursive or forced delete", #"(^|[\s;&|(`"'])rm\s+(?:[^;&|\n]*\s)?(-[a-z]*[rf][a-z]*|--recursive|--force)(\s|$)"#),
        Rule("Runs as root", #"(^|[\s;&|(`"'])(sudo|doas)(\s|$)"#),
        Rule("Force push", #"\bgit\s+(?:-\S+\s+)*push\b[^;&|\n]*(\s--force\b|\s--force-with-lease\b|\s-[a-z]*f[a-z]*(\s|$)|\s\+\S)"#),
        Rule("Discards git changes", #"\bgit\s+(?:-\S+\s+)*(reset\s+--hard|clean\s+-[a-z]*f|checkout\s+(?:--\s+)?\.(\s|$)|restore\s+(?:--\S+\s+)*\.(\s|$)|branch\s+-D\b)"#),
        Rule("Pipes a download into a shell", #"\b(curl|wget|fetch)\b[^\n]*\|\s*(?:sudo\s+)?(?:env\s+\S+\s+)?(?:ba|z|da|k|fi)?sh\b"#),
        Rule("Raw disk or filesystem write", #"(\bdd\s+[^\n]*\bof=|\bmkfs(\.\w+)?\b|>\s*/dev/(?:r?disk|sd)|\bdiskutil\s+(?:erase|partition|zero))"#),
        Rule("Wide permission change", #"\b(chmod|chown)\s+(?:-\S+\s+)*(-R|--recursive)\b|\bchmod\s+(?:-\S+\s+)*[0-7]?777\b"#),
        Rule("Fork bomb", #":\(\)\s*\{"#),
        Rule("Publishes a package", #"\b(npm|pnpm|yarn|cargo|gem|twine)\s+(publish|push|upload)\b"#),
    ]

    private static let sensitiveFragments: [String] = [
        "/.ssh/", "/.aws/", "/.gnupg/", "/.zshrc", "/.zprofile", "/.zshenv", "/.zlogin", "/.profile", "/.bashrc", "/.bash_profile",
        "/.git/hooks/", "/.git/config", "/.claude/", "/library/launchagents/", "/library/launchdaemons/",
        "/etc/", "/.config/gcloud", "/.npmrc", "/.netrc", "/.env", "/.envrc", "/.vscode/tasks.json",
        "/.vscode/launch.json", "/.vscode/settings.json", "/.github/workflows/", "/.husky/", "/makefile",
        "/.config/nubrix/", "/.config/nubrix-run/", "/opt/homebrew/bin/", "/usr/local/bin/", "/.local/bin/",
    ]

    private static let protectedConfigFragments = ["/.config/nubrix"]
    private static let programDirectoryFragments = ["/opt/homebrew/bin/", "/usr/local/bin/", "/.local/bin/"]
    private static let knownShellKeys: Set<String> = ["command", "description", "timeout", "run_in_background", "dangerouslyDisableSandbox"]
    private static let readTools: Set<String> = ["Read", "Glob", "Grep"]

    private static let shellTools: Set<String> = ["Bash", "PowerShell"]
    private static let fileTools: Set<String> = ["Write", "Edit", "MultiEdit", "NotebookEdit"]
    private static let passiveTools: Set<String> = ["WebFetch", "WebSearch"]
    private static let longCommand = 500
    private static let longInput = 2000
    private static let lineWindow = 4096
    private static let lineStride = 3584

    static func assess(toolName: String, input: [String: Any]?, cwd: String?, summary: String? = nil) -> [String] {
        var reasons: [String] = []
        func add(_ reason: String) { if !reasons.contains(reason) { reasons.append(reason) } }

        if shellTools.contains(toolName) {
            guard let command = input?["command"] as? String else { return [] }
            for reason in scan(command) { add(reason) }
            if isTrue(input?["dangerouslyDisableSandbox"]) { add("Runs outside the sandbox") }
            if isTrue(input?["run_in_background"]) { add("Runs in background") }
            if !extraShellInput(input).isEmpty { add("Extra tool input") }
            if writesOutsideProject(command: command, cwd: cwd) { add("Touches files outside the project") }
            for reason in protectedTargets(command: command) { add(reason) }
            if command.contains(where: \.isNewline) { add("Multi-line command") }
            if command.count > longCommand { add("Long command") }
        } else if fileTools.contains(toolName) {
            let path = (input?["file_path"] as? String) ?? (input?["notebook_path"] as? String)
            guard let path, !path.isEmpty else { return [] }
            if isOutside(path, cwd: cwd) { add("Writes outside the project") }
            if isSensitive(path) { add("Sensitive file") }
            if toolName == "Edit", isTrue(input?["replace_all"]) { add("Replaces all occurrences") }
            if toolName == "MultiEdit",
               (input?["edits"] as? [[String: Any]])?.contains(where: { isTrue($0["replace_all"]) }) == true {
                add("Replaces all occurrences")
            }
        } else if readTools.contains(toolName) {
            var candidates: [String] = []
            if toolName == "Read" {
                if let path = input?["file_path"] as? String { candidates.append(path) }
            } else {
                if let path = input?["path"] as? String { candidates.append(path) }
                if let pattern = input?["pattern"] as? String, pattern.hasPrefix("/") || pattern.hasPrefix("~") {
                    candidates.append(pattern)
                }
            }
            let sensitive = candidates.contains { path in
                guard !path.isEmpty else { return false }
                if path.hasPrefix("/") || path.hasPrefix("~") { return isSensitive(path) }
                guard let cwd, !cwd.isEmpty else { return isSensitive(path) }
                return isSensitive((cwd as NSString).appendingPathComponent(path))
            }
            if sensitive { add("Reads a sensitive file") }
        } else if !passiveTools.contains(toolName) {
            let text = summary ?? AgentToolSummary.summary(toolName: toolName, input: input, limit: Int.max)
            for reason in scan(text) { add(reason) }
            if text.count > longInput { add("Very long input") }
        }
        return reasons
    }

    static func isTrue(_ value: Any?) -> Bool {
        if let string = value as? String { return string.lowercased() == "true" }
        return (value as? NSNumber)?.boolValue == true
    }

    static func extraShellInput(_ input: [String: Any]?) -> [String: Any] {
        guard let input else { return [:] }
        return input.filter { !knownShellKeys.contains($0.key) }
    }

    static func scan(_ text: String) -> [String] {
        var found: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let units = Array(line.utf16)
            if units.count <= lineWindow {
                collect(String(line), into: &found)
                continue
            }
            if !found.contains("Very long line") { found.append("Very long line") }
            var offset = 0
            while offset < units.count {
                let end = min(units.count, offset + lineWindow)
                collect(String(decoding: units[offset..<end], as: UTF16.self), into: &found)
                if end == units.count { break }
                offset += lineStride
            }
        }
        return found
    }

    private static func collect(_ chunk: String, into found: inout [String]) {
        for rule in commandRules where !found.contains(rule.reason) && rule.matches(chunk) { found.append(rule.reason) }
    }

    private static func resolved(_ path: String) -> String {
        let expanded = path.hasPrefix("~") ? NSString(string: path).expandingTildeInPath : path
        return URL(fileURLWithPath: (expanded as NSString).standardizingPath).resolvingSymlinksInPath().path
    }

    static func isOutside(_ path: String, cwd: String?) -> Bool {
        guard let cwd, !cwd.isEmpty else { return false }
        let expanded = path.hasPrefix("~") ? NSString(string: path).expandingTildeInPath : path
        guard expanded.hasPrefix("/") else { return expanded.hasPrefix("..") }
        func inside(_ target: String, _ base: String) -> Bool {
            target == base || target.hasPrefix(base.hasSuffix("/") ? base : base + "/")
        }
        let target = (expanded as NSString).standardizingPath
        let base = (cwd as NSString).standardizingPath
        if !inside(target, base) { return true }
        return !inside(resolved(expanded), resolved(cwd))
    }

    static func isSensitive(_ path: String) -> Bool {
        let expanded = path.hasPrefix("~") ? NSString(string: path).expandingTildeInPath : path
        let candidates = [(expanded as NSString).standardizingPath, resolved(expanded)].map { $0.lowercased() }
        return candidates.contains { candidate in sensitiveFragments.contains { candidate.contains($0) } }
    }

    private static let writerCommands: Set<String> = ["rm", "mv", "cp", "tee", "chmod", "chown", "ln", "touch", "mkdir", "rmdir", "truncate", "install"]

    private static func shellTokens(_ command: String) -> [String] {
        command
            .replacingOccurrences(of: ">>", with: " >> ")
            .replacingOccurrences(of: ">", with: " > ")
            .replacingOccurrences(of: ";", with: " ; ")
            .replacingOccurrences(of: "&&", with: " ; ")
            .replacingOccurrences(of: "|", with: " ; ")
            .replacingOccurrences(of: "&", with: " ; ")
            .replacingOccurrences(of: "\n", with: " ; ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
    }

    private static func protectedTargets(command: String) -> [String] {
        var reasons: [String] = []
        var writerActive = false
        var expectTarget = false
        for token in shellTokens(command) {
            if token == ";" { writerActive = false; expectTarget = false; continue }
            if token == ">" || token == ">>" { expectTarget = true; continue }
            if writerCommands.contains(token) { writerActive = true; continue }
            let lowered = token.lowercased()
            if protectedConfigFragments.contains(where: { lowered.contains($0) }),
               !reasons.contains("Touches Nubrix hook or endpoint files") {
                reasons.append("Touches Nubrix hook or endpoint files")
            }
            if expectTarget || writerActive,
               programDirectoryFragments.contains(where: { lowered.contains($0) }),
               !reasons.contains("Writes into a program directory") {
                reasons.append("Writes into a program directory")
            }
            expectTarget = false
        }
        return reasons
    }

    private static func writesOutsideProject(command: String, cwd: String?) -> Bool {
        guard let cwd, !cwd.isEmpty else { return false }
        let tokens = shellTokens(command)
        var writerActive = false
        var expectTarget = false
        for token in tokens {
            if token == ";" { writerActive = false; expectTarget = false; continue }
            if token == ">" || token == ">>" { expectTarget = true; continue }
            if writerCommands.contains(token) { writerActive = true; continue }
            let isPath = token.hasPrefix("/") || token.hasPrefix("~") || token.hasPrefix("..")
            if isPath, expectTarget || writerActive {
                let standard = (token as NSString).standardizingPath
                let exempt = standard == "/dev/null" || standard.hasPrefix("/tmp/") || standard.hasPrefix("/private/tmp/")
                if !exempt, isOutside(token, cwd: cwd) { return true }
            }
            expectTarget = false
        }
        return false
    }
}
