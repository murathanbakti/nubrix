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
        Rule("Recursive or forced delete", #"(^|[\s;&|(`])rm\s+(?:[^;&|\n]*\s)?(-[a-z]*[rf][a-z]*|--recursive|--force)(\s|$)"#),
        Rule("Runs as root", #"(^|[\s;&|(`])(sudo|doas)(\s|$)"#),
        Rule("Force push", #"\bgit\s+(?:-\S+\s+)*push\b[^;&|\n]*(\s--force\b|\s--force-with-lease\b|\s-[a-z]*f[a-z]*(\s|$)|\s\+\S)"#),
        Rule("Discards git changes", #"\bgit\s+(?:-\S+\s+)*(reset\s+--hard|clean\s+-[a-z]*f|checkout\s+(?:--\s+)?\.(\s|$)|restore\s+(?:--\S+\s+)*\.(\s|$)|branch\s+-D\b)"#),
        Rule("Pipes a download into a shell", #"\b(curl|wget|fetch)\b[^\n]*\|\s*(?:sudo\s+)?(?:env\s+\S+\s+)?(?:ba|z|da|k|fi)?sh\b"#),
        Rule("Raw disk or filesystem write", #"(\bdd\s+[^\n]*\bof=|\bmkfs(\.\w+)?\b|>\s*/dev/(?:r?disk|sd)|\bdiskutil\s+(?:erase|partition|zero))"#),
        Rule("Wide permission change", #"\b(chmod|chown)\s+(?:-\S+\s+)*(-R|--recursive)\b|\bchmod\s+(?:-\S+\s+)*[0-7]?777\b"#),
        Rule("Fork bomb", #":\(\)\s*\{"#),
        Rule("Publishes a package", #"\b(npm|pnpm|yarn|cargo|gem|twine)\s+(publish|push|upload)\b"#),
    ]

    private static let sensitiveFragments: [String] = [
        "/.ssh/", "/.aws/", "/.gnupg/", "/.zshrc", "/.zprofile", "/.bashrc", "/.bash_profile",
        "/.git/hooks/", "/.claude/settings", "/Library/LaunchAgents/", "/Library/LaunchDaemons/",
        "/etc/", "/.config/gcloud", "/.npmrc", "/.netrc",
    ]

    static func assess(toolName: String, input: [String: Any]?, cwd: String?) -> [String] {
        var reasons: [String] = []
        func add(_ reason: String) { if !reasons.contains(reason) { reasons.append(reason) } }

        switch toolName {
        case "Bash", "PowerShell":
            guard let command = input?["command"] as? String else { return [] }
            let searchable = String(command.prefix(AgentToolSummary.limit * 4))
            for rule in commandRules where rule.matches(searchable) { add(rule.reason) }
            if writesOutsideProject(command: searchable, cwd: cwd) { add("Touches files outside the project") }
        case "Write", "Edit", "MultiEdit", "NotebookEdit":
            let path = (input?["file_path"] as? String) ?? (input?["notebook_path"] as? String)
            guard let path, !path.isEmpty else { return [] }
            if isOutside(path, cwd: cwd) { add("Writes outside the project") }
            if isSensitive(path) { add("Sensitive file") }
        default:
            break
        }
        return reasons
    }

    static func isOutside(_ path: String, cwd: String?) -> Bool {
        guard let cwd, !cwd.isEmpty else { return false }
        let expanded = path.hasPrefix("~") ? NSString(string: path).expandingTildeInPath : path
        guard expanded.hasPrefix("/") else { return expanded.hasPrefix("..") }
        let target = (expanded as NSString).standardizingPath
        let base = (cwd as NSString).standardizingPath
        return !(target == base || target.hasPrefix(base.hasSuffix("/") ? base : base + "/"))
    }

    static func isSensitive(_ path: String) -> Bool {
        let expanded = path.hasPrefix("~") ? NSString(string: path).expandingTildeInPath : path
        let standardized = (expanded as NSString).standardizingPath
        return sensitiveFragments.contains { standardized.contains($0) }
    }

    private static let writerCommands: Set<String> = ["rm", "mv", "cp", "tee", "chmod", "chown", "ln", "touch", "mkdir", "rmdir", "truncate", "install"]

    private static func writesOutsideProject(command: String, cwd: String?) -> Bool {
        guard let cwd, !cwd.isEmpty else { return false }
        let tokens = command
            .replacingOccurrences(of: ">>", with: " >> ")
            .replacingOccurrences(of: ">", with: " > ")
            .replacingOccurrences(of: ";", with: " ; ")
            .replacingOccurrences(of: "&&", with: " ; ")
            .replacingOccurrences(of: "|", with: " ; ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }
        var writerActive = false
        var expectTarget = false
        for token in tokens {
            if token == ";" { writerActive = false; expectTarget = false; continue }
            if token == ">" || token == ">>" { expectTarget = true; continue }
            if writerCommands.contains(token) { writerActive = true; continue }
            let isPath = token.hasPrefix("/") || token.hasPrefix("~") || token.hasPrefix("..")
            if isPath, (expectTarget || writerActive), !token.hasPrefix("/dev/null"), !token.hasPrefix("/tmp/"), !token.hasPrefix("/private/tmp/"), isOutside(token, cwd: cwd) {
                return true
            }
            expectTarget = false
        }
        return false
    }
}
