import Foundation

struct ClipClassification: Equatable {
    let kind: ClipKind
    let content: String
}

enum ClipClassifier {
    static let maxTextLength = 256_000

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
