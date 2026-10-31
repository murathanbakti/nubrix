import Foundation
import SwiftUI

enum ClipHighlighter {
    static let maxChars = 4096
    static let maxLines = 200
    static let previewSourceLimit = 40_000

    private struct Grammar {
        let comment: String
        let string: String
        let number: String
        let keyword: String
    }

    private static let plainNumber = #"\b(?:0[xX][0-9a-fA-F]+|\d+(?:\.\d+)?)\b"#
    private static let quotes = #""(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'"#
    private static let cComment = #"//[^\n]*|/\*[\s\S]*?\*/"#
    private static let hashComment = #"#[^\n]*"#

    private static func words(_ list: String) -> String {
        #"\b(?:"# + list.split(separator: " ").joined(separator: "|") + #")\b"#
    }

    private static func grammar(for language: CodeLanguage?) -> Grammar {
        switch language {
        case .swift:
            return Grammar(comment: cComment, string: #""""[\s\S]*?"""|"(?:\\.|[^"\\\n])*""#, number: plainNumber,
                           keyword: words("func let var if else guard return struct class enum extension protocol import in for while switch case default break continue self Self init deinit nil true false try catch throw throws async await some any static private public internal fileprivate final override where as is do defer typealias weak lazy mutating") + #"|@\w+"#)
        case .typescript, .javascript:
            return Grammar(comment: cComment, string: quotes + #"|`(?:\\.|[^`\\])*`"#, number: plainNumber,
                           keyword: words("const let var function return if else for while switch case default break continue class extends new this import export from as async await try catch throw typeof instanceof null undefined true false interface type enum implements public private readonly static of in yield void delete"))
        case .python:
            return Grammar(comment: hashComment, string: #""""[\s\S]*?"""|'''[\s\S]*?'''|"# + quotes, number: plainNumber,
                           keyword: words("def class return if elif else for while in not and or is import from as with try except finally raise pass break continue lambda yield None True False self async await global nonlocal assert del") + #"|@\w+"#)
        case .go:
            return Grammar(comment: cComment, string: quotes + #"|`[^`]*`"#, number: plainNumber,
                           keyword: words("package import func var const type struct interface map chan go defer return if else for range switch case default break continue select nil true false fallthrough"))
        case .rust:
            return Grammar(comment: cComment, string: #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\\n])'"#, number: plainNumber,
                           keyword: words("fn let mut const static struct enum impl trait pub use mod crate self Self super return if else match for while loop in break continue as ref move async await dyn where type unsafe true false None Some Ok Err") + #"|#!?\[[^\]\n]*\]"#)
        case .sql:
            return Grammar(comment: #"--[^\n]*|/\*[\s\S]*?\*/"#, string: #"'(?:''|[^'])*'|"(?:\\.|[^"\\\n])*""#, number: plainNumber,
                           keyword: #"(?i)\b(?:select|from|where|insert|into|values|update|set|delete|create|table|index|view|alter|drop|join|inner|left|right|full|outer|cross|on|group|by|order|having|limit|offset|as|and|or|not|null|is|in|like|between|distinct|union|all|primary|key|foreign|references|default|unique|count|sum|avg|min|max|asc|desc|case|when|then|else|end)\b"#)
        case .shell:
            return Grammar(comment: hashComment, string: quotes, number: plainNumber,
                           keyword: words("if then else elif fi for while do done case esac function in return export local source alias unset set echo cd sudo exit") + #"|\$\{?\w+\}?"#)
        case .yaml:
            return Grammar(comment: hashComment, string: quotes, number: plainNumber,
                           keyword: #"(?m)^[ \t\-]*[\w.\-]+(?=:)|\b(?:true|false|null|yes|no)\b"#)
        case .html:
            return Grammar(comment: #"<!--[\s\S]*?-->"#, string: #""[^"\n]*""#, number: #"(?!)"#,
                           keyword: #"</?[A-Za-z][\w\-]*|/?>|<!DOCTYPE"#)
        case .css:
            return Grammar(comment: #"/\*[\s\S]*?\*/"#, string: quotes,
                           number: #"#[0-9a-fA-F]{3,8}\b|\b\d+(?:\.\d+)?(?:px|rem|em|vh|vw|ms|s|%)?"#,
                           keyword: #"@[a-z\-]+|!important|[a-z\-]+(?=\s*:(?!:))"#)
        case .json:
            return Grammar(comment: #"(?!)"#, string: #""(?:\\.|[^"\\\n])*""#, number: #"-?\b\d+(?:\.\d+)?(?:[eE][+\-]?\d+)?\b"#,
                           keyword: words("true false null"))
        case nil:
            return Grammar(comment: cComment + "|" + hashComment, string: quotes, number: plainNumber,
                           keyword: words("func function def class struct enum interface let var const return if else for while switch case import export from new this self null nil true false void public private static"))
        }
    }

    private static let compiled: [String: NSRegularExpression] = {
        var result: [String: NSRegularExpression] = [:]
        for language in CodeLanguage.allCases {
            if let regex = makeRegex(grammar(for: language)) { result[language.rawValue] = regex }
        }
        if let regex = makeRegex(grammar(for: nil)) { result["generic"] = regex }
        return result
    }()

    private static func makeRegex(_ g: Grammar) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: "(\(g.comment))|(\(g.string))|(\(g.number))|(\(g.keyword))", options: [.anchorsMatchLines])
    }

    static var uncompiledCount: Int { CodeLanguage.allCases.count + 1 - compiled.count }

    private static let commentColor = Color(red: 0.45, green: 0.58, blue: 0.47)
    private static let stringColor = Color(red: 0.98, green: 0.62, blue: 0.40)
    private static let numberColor = Color(red: 0.52, green: 0.76, blue: 1.0)
    private static let keywordColor = Color(red: 0.96, green: 0.47, blue: 0.78)

    static func limited(_ text: String, maxChars: Int, maxLines: Int) -> (head: String, truncated: Bool) {
        let head = text.prefix(maxChars)
        var count = 0
        var cut = head.endIndex
        for i in head.indices where head[i] == "\n" {
            count += 1
            if count == maxLines {
                cut = i
                break
            }
        }
        let result = String(head[head.startIndex..<cut])
        return (result, result.count < text.count)
    }

    static func highlight(_ text: String, language: CodeLanguage?, maxChars: Int = maxChars, maxLines: Int = maxLines) -> AttributedString {
        let (head, truncated) = limited(text, maxChars: maxChars, maxLines: maxLines)
        var result = highlightPrefix(head, language: language)
        if truncated { result += AttributedString("\n\u{2026}") }
        return result
    }

    static func previewText(_ text: String, language: CodeLanguage?, totalLength: Int? = nil, tailLimit: Int = 20_000) -> AttributedString {
        let (head, truncated) = limited(text, maxChars: maxChars, maxLines: maxLines)
        var result = highlightPrefix(head, language: language)
        guard truncated else { return result }
        let rest = text.dropFirst(head.count)
        let tail = rest.prefix(tailLimit)
        result += AttributedString(String(tail))
        let remaining = (totalLength ?? text.count) - head.count - tailLimit
        if remaining > 0 {
            result += AttributedString("\n\u{2026} \(remaining) more characters")
        }
        return result
    }

    private static func highlightPrefix(_ head: String, language: CodeLanguage?) -> AttributedString {
        guard !head.isEmpty else { return AttributedString() }
        guard let regex = compiled[language?.rawValue ?? "generic"] else { return AttributedString(head) }
        let ns = head as NSString
        var result = AttributedString()
        var cursor = 0
        regex.enumerateMatches(in: head, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match, match.range.length > 0, match.range.location >= cursor else { return }
            var color: Color?
            for (group, candidate) in [commentColor, stringColor, numberColor, keywordColor].enumerated()
            where match.range(at: group + 1).location != NSNotFound {
                color = candidate
                break
            }
            if match.range.location > cursor {
                result += AttributedString(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            var piece = AttributedString(ns.substring(with: match.range))
            piece.foregroundColor = color
            result += piece
            cursor = match.range.location + match.range.length
        }
        if cursor < ns.length {
            result += AttributedString(ns.substring(from: cursor))
        }
        return result
    }
}
