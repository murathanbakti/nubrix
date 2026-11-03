import Foundation

final class ClipSearchIndex {
    static let maxBytesPerItem = 65_536

    private struct Entry {
        var used: Double
        let text: [UInt8]
    }

    private var entries: [Int64: Entry] = [:]

    var count: Int { entries.count }

    static func fold(_ s: String) -> [UInt8] {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return Array(folded.utf8.prefix(maxBytesPerItem))
    }

    func insert(id: Int64, used: Double, text: String) {
        entries[id] = Entry(used: used, text: Self.fold(text))
    }

    func touch(id: Int64, used: Double) {
        entries[id]?.used = used
    }

    func remove(id: Int64) {
        entries[id] = nil
    }

    func search(_ raw: String, limit: Int) -> [Int64] {
        guard limit > 0 else { return [] }
        let tokens = raw
            .split(whereSeparator: { $0.isWhitespace })
            .map { Self.fold(String($0)) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        var matches: [(id: Int64, used: Double)] = []
        for (id, entry) in entries where Self.matches(entry.text, tokens: tokens) {
            matches.append((id, entry.used))
        }
        matches.sort { lhs, rhs in
            lhs.used != rhs.used ? lhs.used > rhs.used : lhs.id > rhs.id
        }
        return matches.prefix(limit).map(\.id)
    }

    private static func matches(_ text: [UInt8], tokens: [[UInt8]]) -> Bool {
        text.withUnsafeBytes { hay in
            guard let hayBase = hay.baseAddress else { return false }
            for token in tokens {
                if token.count > hay.count { return false }
                let found = token.withUnsafeBytes { needle -> Bool in
                    guard let needleBase = needle.baseAddress else { return false }
                    return memmem(hayBase, hay.count, needleBase, needle.count) != nil
                }
                if !found { return false }
            }
            return true
        }
    }
}
