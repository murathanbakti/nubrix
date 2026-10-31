import Foundation

struct ClipInsightEntry: @unchecked Sendable {
    let insight: ClipInsight?
    let looksLikeCode: Bool
    let cardText: AttributedString?
}

@MainActor
final class ClipInsightCache {
    static let shared = ClipInsightCache()

    private final class EntryBox {
        let entry: ClipInsightEntry
        init(_ entry: ClipInsightEntry) { self.entry = entry }
    }

    private final class TextBox {
        let text: AttributedString
        init(_ text: AttributedString) { self.text = text }
    }

    private let entries = NSCache<NSNumber, EntryBox>()
    private let previewTexts = NSCache<NSNumber, TextBox>()
    private var inflightEntries: [Int64: Task<ClipInsightEntry, Never>] = [:]
    private var inflightPreviews: [Int64: Task<AttributedString, Never>] = [:]

    private init() {
        entries.countLimit = 600
        entries.totalCostLimit = 8 * 1024 * 1024
        previewTexts.countLimit = 8
    }

    func cachedEntry(id: Int64) -> ClipInsightEntry? {
        entries.object(forKey: NSNumber(value: id))?.entry
    }

    func forget(id: Int64) {
        entries.removeObject(forKey: NSNumber(value: id))
        previewTexts.removeObject(forKey: NSNumber(value: id))
    }

    func removeAll() {
        entries.removeAllObjects()
        previewTexts.removeAllObjects()
    }

    func entry(for item: ClipItem) async -> ClipInsightEntry? {
        guard item.kind != .image else { return nil }
        if let cached = cachedEntry(id: item.id) { return cached }
        if let running = inflightEntries[item.id] { return await running.value }
        let analyzable = item.textLength <= ClipInsightAnalyzer.maxAnalyzedLength
        let kind = item.kind
        let id = item.id
        let store = ClipStore.shared
        let task = Task<ClipInsightEntry, Never> {
            let text = (analyzable ? await store.fullText(for: item) : item.preview) ?? ""
            return await Task.detached(priority: .utility) {
                Self.compute(kind: kind, text: text, analyzable: analyzable)
            }.value
        }
        inflightEntries[id] = task
        let result = await task.value
        inflightEntries[id] = nil
        entries.setObject(EntryBox(result), forKey: NSNumber(value: id), cost: min(item.textLength, ClipInsightAnalyzer.maxAnalyzedLength) * 2 + 512)
        return result
    }

    func previewText(for item: ClipItem, language: CodeLanguage?) async -> AttributedString {
        let key = NSNumber(value: item.id)
        if let box = previewTexts.object(forKey: key) { return box.text }
        if let running = inflightPreviews[item.id] { return await running.value }
        let id = item.id
        let length = item.textLength
        let store = ClipStore.shared
        let task = Task<AttributedString, Never> {
            let text = await store.fullText(for: item, maxChars: ClipHighlighter.previewSourceLimit) ?? ""
            return await Task.detached(priority: .userInitiated) {
                ClipHighlighter.previewText(text, language: language, totalLength: length)
            }.value
        }
        inflightPreviews[id] = task
        let result = await task.value
        inflightPreviews[id] = nil
        previewTexts.setObject(TextBox(result), forKey: key)
        return result
    }

    nonisolated static func compute(kind: ClipKind, text: String, analyzable: Bool) -> ClipInsightEntry {
        let insight: ClipInsight? = analyzable
            ? (kind == .link ? ClipInsightAnalyzer.analyzeLink(text) : ClipInsightAnalyzer.analyze(text))
            : nil
        let code = insight?.isCode ?? ClipClassifier.looksLikeCode(text)
        var cardText: AttributedString?
        if kind == .text, insight?.color == nil, code {
            cardText = ClipHighlighter.highlight(String(text.prefix(400)), language: insight?.language, maxChars: 400, maxLines: 14)
        }
        return ClipInsightEntry(insight: insight, looksLikeCode: code, cardText: cardText)
    }
}
