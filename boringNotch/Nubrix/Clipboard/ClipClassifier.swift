import Foundation

struct ClipClassification: Equatable {
    let kind: ClipKind
    let content: String
}

enum ClipClassifier {
    static let maxTextLength = 1_000_000

    static func classify(_ text: String) -> ClipClassification? {
        guard text.utf16.count <= maxTextLength else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if standaloneURL(trimmed) != nil {
            if SecretGuard.looksLikeSecret(trimmed, isURL: true) { return nil }
            return ClipClassification(kind: .link, content: trimmed)
        }
        if SecretGuard.looksLikeSecret(text, isURL: false) { return nil }
        return ClipClassification(kind: .text, content: text)
    }

    static func standaloneURL(_ text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 8192,
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func looksLikeCode(_ text: String) -> Bool {
        let sample = String(text.prefix(2000))
        guard sample.count >= 8 else { return false }
        let lines = sample.split(separator: "\n", omittingEmptySubsequences: true)
        let keywordPrefixes = ["func ", "def ", "class ", "import ", "const ", "let ", "var ", "function ", "#include", "public ", "private ", "return ", "if (", "for (", "struct ", "enum ", "export ", "SELECT ", "<?php", "package "]
        let keywordHits = lines.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return keywordPrefixes.contains { t.hasPrefix($0) }
        }.count
        if keywordHits > 0 && lines.count >= 2 { return true }
        let symbols = Set("{}[]();=<>/\\|&*#$@^~`")
        let symbolCount = sample.filter { symbols.contains($0) }.count
        let density = Double(symbolCount) / Double(sample.count)
        if density > 0.08 { return true }
        if lines.count >= 3 {
            let indented = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }.count
            let terminated = lines.filter { l in
                guard let last = l.trimmingCharacters(in: .whitespaces).last else { return false }
                return ";{}),".contains(last)
            }.count
            if Double(indented) / Double(lines.count) >= 0.3 && terminated > 0 { return true }
            if Double(terminated) / Double(lines.count) >= 0.5 { return true }
        }
        return false
    }
}

enum SecretGuard {
    private static let patterns: [NSRegularExpression] = [
        "-----BEGIN [A-Z0-9 ]*PRIVATE KEY",
        "\\bsk-[A-Za-z0-9_\\-]{20,}",
        "\\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}",
        "\\bgithub_pat_[A-Za-z0-9_]{20,}",
        "\\b(?:AKIA|ASIA)[0-9A-Z]{16}\\b",
        "\\bxox[abprs]-[A-Za-z0-9-]{10,}",
        "\\beyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]*"
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static let bearer = try? NSRegularExpression(pattern: "\\bbearer\\s+([A-Za-z0-9._~+/=\\-]{16,})", options: [.caseInsensitive])

    static func looksLikeSecret(_ text: String, isURL: Bool) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns where pattern.firstMatch(in: text, range: range) != nil {
            return true
        }
        if let bearer {
            for match in bearer.matches(in: text, range: range) where match.numberOfRanges > 1 {
                if let r = Range(match.range(at: 1), in: text), text[r].contains(where: \.isNumber) {
                    return true
                }
            }
        }
        if !isURL { return looksLikeOpaqueToken(text) }
        return false
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
