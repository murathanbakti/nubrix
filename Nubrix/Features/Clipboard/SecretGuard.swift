import Foundation

enum SecretGuard {
    private static func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: options)
    }

    private static let patterns: [NSRegularExpression] = [
        "-----BEGIN [A-Z0-9 ]*PRIVATE KEY",
        "\\bsk-[A-Za-z0-9_\\-]{20,}",
        "\\b[rs]k_(?:live|test)_[A-Za-z0-9]{16,}",
        "\\bwhsec_[A-Za-z0-9]{16,}",
        "\\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}",
        "\\bgithub_pat_[A-Za-z0-9_]{20,}",
        "\\bglpat-[A-Za-z0-9_\\-]{20,}",
        "\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b",
        "\\bxox[abeoprs]-[A-Za-z0-9-]{10,}",
        "\\bSG\\.[A-Za-z0-9_\\-]{16,}\\.[A-Za-z0-9_\\-]{16,}",
        "\\bnpm_[A-Za-z0-9]{30,}",
        "\\bAIza[A-Za-z0-9_\\-]{35}",
        "\\b(?:SK|AC)[0-9a-f]{32}\\b",
        "\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]*",
        "hooks\\.slack\\.com/(?:services|workflows|triggers)/[A-Za-z0-9/_\\-]{8,}",
        "discord(?:app)?\\.com/api/(?:v\\d+/)?webhooks/\\d+/[A-Za-z0-9_\\-]{20,}",
        "\\b[A-Za-z][A-Za-z0-9+.\\-]{1,15}://[^\\s/:@?#]+:[^\\s/@?#]+@"
    ].compactMap { regex($0) }

    private static let authorizationBasic = regex("authorization:\\s*basic\\s+[A-Za-z0-9+/=]{12,}", [.caseInsensitive])
    private static let bearer = regex("\\bbearer\\s+([A-Za-z0-9._~+/=\\-]{16,})", [.caseInsensitive])
    private static let queryPair = regex("[?&;#]([A-Za-z0-9_.\\-]{2,40})=([^&\\s#\"']+)")
    private static let assignment = regex("^[ \\t]*(?:export[ \\t]+|set[ \\t]+|declare[ \\t]+-x[ \\t]+)?[\"']?([A-Za-z][A-Za-z0-9_.\\-]*)[\"']?[ \\t]*(?:=|:)[ \\t]*(.*)$", [.anchorsMatchLines])
    private static let cardCandidate = regex("(?<![\\w.])\\d(?:[ -]?\\d){12,18}(?![\\w])")

    private static let strongQueryKeys: Set<String> = [
        "x-amz-signature", "x-amz-security-token", "x-goog-signature", "signature", "sig",
        "token", "access_token", "id_token", "refresh_token", "auth_token", "sas_token",
        "api_key", "apikey", "api-key", "x-api-key", "secret", "client_secret", "password", "passwd", "pwd"
    ]
    private static let weakQueryKeys: Set<String> = ["key", "code", "auth", "session", "sessionid", "sid", "jwt"]

    private static let passwordWords: Set<String> = ["password", "passwd", "pwd", "pass", "passphrase", "passcode"]
    private static let secretWords: Set<String> = ["secret", "token", "credential", "credentials", "apikey", "auth", "authorization", "bearer"]
    private static let keyWords: Set<String> = ["key"]
    private static let inertSuffixes: Set<String> = [
        "url", "uri", "path", "file", "dir", "name", "id", "type", "endpoint", "host", "length", "size", "count",
        "expiry", "expires", "ttl", "enabled", "mode", "field", "header", "prefix", "label", "placeholder",
        "hint", "regex", "pattern", "status", "policy", "provider", "algorithm", "format", "version", "error"
    ]
    private static let inertValues: Set<String> = [
        "true", "false", "null", "none", "nil", "yes", "no", "required", "optional", "string", "hidden", "secret",
        "password", "token", "example", "placeholder", "undefined", "todo", "redacted", "masked", "changeme",
        "string?", "bool", "boolean", "number", "int", "empty", "default", "value", "your_password", "your_token"
    ]
    private static let inertValuePrefixes = ["$", "<", "{", "[", "%", "(", "/", "~", "./", "../", "@", "#"]

    static func looksLikeSecret(_ text: String, isURL: Bool) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns where pattern.firstMatch(in: text, range: range) != nil {
            return true
        }
        if let authorizationBasic, authorizationBasic.firstMatch(in: text, range: range) != nil {
            return true
        }
        if let bearer {
            for match in bearer.matches(in: text, range: range) where match.numberOfRanges > 1 {
                if let r = Range(match.range(at: 1), in: text), text[r].contains(where: \.isNumber) {
                    return true
                }
            }
        }
        if hasSensitiveQuery(text, range: range) { return true }
        if containsCardNumber(text, range: range) { return true }
        if isURL { return false }
        if hasSecretAssignment(text) { return true }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeHexToken(token) { return true }
        if looksLikeOpaqueToken(token) { return true }
        return looksLikePasswordToken(token)
    }

    static func hasSensitiveQuery(_ text: String, range: NSRange) -> Bool {
        guard let queryPair, text.contains("=") else { return false }
        for match in queryPair.matches(in: text, range: range) where match.numberOfRanges > 2 {
            guard let kr = Range(match.range(at: 1), in: text), let vr = Range(match.range(at: 2), in: text) else { continue }
            let key = text[kr].lowercased()
            let value = text[vr]
            if strongQueryKeys.contains(key) {
                if value.count >= 8 { return true }
            } else if weakQueryKeys.contains(key) {
                if value.count >= 20, value.contains(where: \.isNumber), value.contains(where: \.isLetter) { return true }
            }
        }
        return false
    }

    static func containsCardNumber(_ text: String, range: NSRange) -> Bool {
        guard let cardCandidate else { return false }
        for match in cardCandidate.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let digits = text[r].filter(\.isNumber)
            if isCardNumber(String(digits)) { return true }
        }
        return false
    }

    static func isCardNumber(_ digits: String) -> Bool {
        let values = digits.compactMap { $0.wholeNumberValue }
        guard values.count == digits.count, (13...19).contains(values.count), Set(values).count > 1 else { return false }
        guard hasCardPrefix(values) else { return false }
        var sum = 0
        for (offset, value) in values.reversed().enumerated() {
            if offset % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return sum % 10 == 0
    }

    private static func hasCardPrefix(_ v: [Int]) -> Bool {
        func prefix(_ n: Int) -> Int { v.prefix(n).reduce(0) { $0 * 10 + $1 } }
        let count = v.count
        if v[0] == 4 { return count == 13 || count == 16 || count == 19 }
        if (51...55).contains(prefix(2)) || (2221...2720).contains(prefix(4)) { return count == 16 }
        if prefix(2) == 34 || prefix(2) == 37 { return count == 15 }
        if prefix(4) == 6011 || prefix(2) == 65 || (644...649).contains(prefix(3)) || prefix(2) == 62 { return (16...19).contains(count) }
        if prefix(2) == 36 || prefix(2) == 38 || (300...305).contains(prefix(3)) { return count == 14 }
        if prefix(2) == 35 { return (16...19).contains(count) }
        return false
    }

    static func hasSecretAssignment(_ text: String) -> Bool {
        guard let assignment, text.contains(where: { $0 == "=" || $0 == ":" }) else { return false }
        var checked = 0
        var found = false
        text.enumerateLines { line, stop in
            checked += 1
            if checked > 5000 { stop = true; return }
            guard line.utf8.count <= 4000 else { return }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = assignment.firstMatch(in: line, range: range), match.numberOfRanges > 2,
                  let nr = Range(match.range(at: 1), in: line), let vr = Range(match.range(at: 2), in: line) else { return }
            if secretAssignment(name: String(line[nr]), rawValue: String(line[vr])) {
                found = true
                stop = true
            }
        }
        return found
    }

    enum NameKind { case password, secret, key }

    static func nameKind(_ name: String) -> NameKind? {
        var words: [String] = []
        var current = ""
        var previousLower = false
        for ch in name {
            if ch == "_" || ch == "." || ch == "-" {
                if !current.isEmpty { words.append(current.lowercased()); current = "" }
                previousLower = false
                continue
            }
            if ch.isUppercase, previousLower, !current.isEmpty {
                words.append(current.lowercased())
                current = ""
            }
            current.append(ch)
            previousLower = ch.isLowercase || ch.isNumber
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        guard let last = words.last, !inertSuffixes.contains(last) else { return nil }
        if words.contains(where: { passwordWords.contains($0) }) { return .password }
        if words.contains(where: { secretWords.contains($0) }) { return .secret }
        if words.contains(where: { keyWords.contains($0) }) { return .key }
        return nil
    }

    static func secretAssignment(name: String, rawValue: String) -> Bool {
        guard let kind = nameKind(name) else { return false }
        var value = rawValue.trimmingCharacters(in: .whitespaces)
        if let first = value.first, first == "\"" || first == "'" || first == "`" {
            value.removeFirst()
            if let end = value.firstIndex(of: first) { value = String(value[..<end]) }
        } else if let space = value.firstIndex(where: { $0 == " " || $0 == "\t" }) {
            value = String(value[..<space])
        }
        while let last = value.last, last == "," || last == ";" || last == "\"" || last == "'" { value.removeLast() }
        guard !value.isEmpty, !value.contains(where: { $0.isWhitespace }) else { return false }
        if inertValues.contains(value.lowercased()) { return false }
        if inertValuePrefixes.contains(where: { value.hasPrefix($0) }) { return false }
        if value.contains("(") || value.contains(")") || value.contains("://") { return false }
        let lowered = value.lowercased()
        if lowered.contains("process.env") || lowered.contains("getenv") || lowered.contains("environ") || lowered.hasPrefix("env.") { return false }
        if Set(value).count == 1 { return false }
        if value.range(of: "^[A-Za-z_][A-Za-z_]*(\\.[A-Za-z_][A-Za-z_]*)+$", options: .regularExpression) != nil { return false }
        let classes = characterClasses(value)
        switch kind {
        case .password:
            return value.count >= 6 && (classes >= 2 || value.count >= 12)
        case .secret:
            return value.count >= 8 && (classes >= 2 || value.count >= 20)
        case .key:
            return (value.count >= 12 && value.contains(where: \.isNumber) && classes >= 2) || value.count >= 24
        }
    }

    static func characterClasses(_ s: String) -> Int {
        var lower = false, upper = false, digit = false, other = false
        for ch in s {
            if ch.isLowercase { lower = true }
            else if ch.isUppercase { upper = true }
            else if ch.isNumber { digit = true }
            else { other = true }
        }
        return [lower, upper, digit, other].filter { $0 }.count
    }

    static func looksLikeHexToken(_ token: String) -> Bool {
        guard token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        var hex = Substring(token)
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex = hex.dropFirst(2) }
        guard hex.count >= 32, hex.count != 40, hex.allSatisfy(\.isHexDigit) else { return false }
        return Set(hex.lowercased()).count >= 6
    }

    static func looksLikePasswordToken(_ token: String) -> Bool {
        guard (8...64).contains(token.count), token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        guard !token.contains("/"), !token.contains("\\"), !token.contains("://") else { return false }
        guard let first = token.first, first != "@", first != "#" else { return false }
        if token.range(of: "^[^@\\s]+@[^@\\s]+\\.[A-Za-z]{2,}$", options: .regularExpression) != nil { return false }
        if token.contains("(") && token.contains(")") { return false }
        if token.range(of: "\\d\\.\\d", options: .regularExpression) != nil { return false }
        var upper = false, lower = false, digit = false
        var specials = 0
        let specialSet = Set("!$%^&*()+=?~<>{}[]|;,'\"@#`")
        for ch in token {
            if ch.isUppercase { upper = true }
            else if ch.isLowercase { lower = true }
            else if ch.isNumber { digit = true }
            else if specialSet.contains(ch) { specials += 1 }
        }
        guard upper, lower, digit, specials >= 1 else { return false }
        return specials >= 2 || token.count >= 10
    }

    static func looksLikeOpaqueToken(_ text: String) -> Bool {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 32, token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
        guard token.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard !token.hasPrefix("/"), !token.contains("//") else { return false }
        guard token.contains(where: \.isNumber), token.contains(where: \.isLetter) else { return false }
        return entropy(token) >= 4.0
    }

    static func entropy(_ s: String) -> Double {
        var counts: [Character: Int] = [:]
        for c in s { counts[c, default: 0] += 1 }
        let n = Double(s.count)
        return counts.values.reduce(0.0) { acc, c in
            let p = Double(c) / n
            return acc - p * log2(p)
        }
    }
}
