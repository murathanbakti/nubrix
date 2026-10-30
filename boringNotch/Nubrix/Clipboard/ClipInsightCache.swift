import Foundation

final class ClipInsightCache: @unchecked Sendable {
    static let shared = ClipInsightCache()

    private final class InsightBox {
        let insight: ClipInsight?
        let length: Int
        init(insight: ClipInsight?, length: Int) {
            self.insight = insight
            self.length = length
        }
    }

    private final class TextBox {
        let text: AttributedString
        let length: Int
        init(text: AttributedString, length: Int) {
            self.text = text
            self.length = length
        }
    }

    private let insights = NSCache<NSNumber, InsightBox>()
    private let cardTexts = NSCache<NSNumber, TextBox>()
    private let previewTexts = NSCache<NSNumber, TextBox>()

    private init() {
        insights.countLimit = 600
        cardTexts.countLimit = 300
        previewTexts.countLimit = 8
    }

    func insight(for item: ClipItem) -> ClipInsight? {
        guard let text = item.text, item.kind != .image else { return nil }
        let key = NSNumber(value: item.id)
        if let box = insights.object(forKey: key), box.length == text.utf8.count { return box.insight }
        let result = item.kind == .link ? ClipInsightAnalyzer.analyzeLink(text) : ClipInsightAnalyzer.analyze(text)
        insights.setObject(InsightBox(insight: result, length: text.utf8.count), forKey: key)
        return result
    }

    func cardText(for item: ClipItem, language: CodeLanguage?) -> AttributedString {
        let text = item.text ?? ""
        let key = NSNumber(value: item.id)
        if let box = cardTexts.object(forKey: key), box.length == text.utf8.count { return box.text }
        let result = ClipHighlighter.highlight(String(text.prefix(400)), language: language, maxChars: 400, maxLines: 14)
        cardTexts.setObject(TextBox(text: result, length: text.utf8.count), forKey: key)
        return result
    }

    func previewText(for item: ClipItem, language: CodeLanguage?) -> AttributedString {
        let text = item.text ?? ""
        let key = NSNumber(value: item.id)
        if let box = previewTexts.object(forKey: key), box.length == text.utf8.count { return box.text }
        let result = ClipHighlighter.previewText(text, language: language)
        previewTexts.setObject(TextBox(text: result, length: text.utf8.count), forKey: key)
        return result
    }
}
