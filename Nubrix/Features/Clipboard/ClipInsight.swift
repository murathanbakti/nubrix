import Foundation

enum CodeLanguage: String, CaseIterable {
    case swift = "Swift"
    case typescript = "TypeScript"
    case javascript = "JavaScript"
    case python = "Python"
    case go = "Go"
    case rust = "Rust"
    case sql = "SQL"
    case shell = "Shell"
    case yaml = "YAML"
    case html = "HTML"
    case css = "CSS"
    case json = "JSON"
}

enum ClipInsightKind: Equatable {
    case json
    case color
    case timestamp
    case uuid
    case code(CodeLanguage?)
    case base64
    case urlEncoded
}

struct InsightColor: Equatable {
    var red: Int
    var green: Int
    var blue: Int
    var alpha: Double

    var hex: String {
        var value = String(format: "#%02X%02X%02X", red, green, blue)
        if alpha < 1 { value += String(format: "%02X", Int((alpha * 255).rounded())) }
        return value
    }

    var rgb: String {
        if alpha >= 1 { return "rgb(\(red), \(green), \(blue))" }
        var a = String(format: "%.2f", alpha)
        while a.hasSuffix("0") { a.removeLast() }
        if a.hasSuffix(".") { a.removeLast() }
        return "rgba(\(red), \(green), \(blue), \(a.isEmpty ? "0" : a))"
    }
}

struct ClipInsightAction: Identifiable, @unchecked Sendable {
    let title: String
    private let make: () -> String

    var id: String { title }
    var output: String { make() }

    init(title: String, make: @escaping () -> String) {
        self.title = title
        self.make = make
    }
}

struct ClipInsight: @unchecked Sendable {
    let kind: ClipInsightKind
    let label: String
    let color: InsightColor?
    let date: String?
    let actions: [ClipInsightAction]

    var language: CodeLanguage? {
        switch kind {
        case .json: return .json
        case .code(let language): return language
        default: return nil
        }
    }

    var isCode: Bool {
        switch kind {
        case .json, .code: return true
        default: return false
        }
    }
}

enum ClipInsightAnalyzer {
    static let maxCodeSample = 4000
    static let maxAnalyzedLength = 64_000

    static func analyze(_ text: String) -> ClipInsight? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let extra = percentAction(for: text)

        if let actions = jsonActions(trimmed) {
            return ClipInsight(kind: .json, label: "JSON", color: nil, date: nil, actions: actions + extra)
        }
        if let color = parseColor(trimmed) {
            var actions: [ClipInsightAction] = []
            if color.hex.caseInsensitiveCompare(trimmed) != .orderedSame {
                actions.append(ClipInsightAction(title: "Copy hex") { color.hex })
            }
            if color.rgb.caseInsensitiveCompare(trimmed) != .orderedSame {
                actions.append(ClipInsightAction(title: "Copy rgb()") { color.rgb })
            }
            return ClipInsight(kind: .color, label: color.hex, color: color, date: nil, actions: actions + extra)
        }
        if let seconds = timestampSeconds(trimmed) {
            let isMillis = trimmed.utf8.count == 13
            let actions = [
                ClipInsightAction(title: "Copy ISO 8601 date") { isoString(seconds, fractional: isMillis) },
                ClipInsightAction(title: "Copy local date") { localString(seconds) }
            ]
            return ClipInsight(kind: .timestamp, label: "Time", color: nil, date: humanString(seconds), actions: actions + extra)
        }
        if trimmed.utf8.count == 36, let uuid = UUID(uuidString: trimmed) {
            let lower = uuid.uuidString.lowercased()
            let upper = uuid.uuidString
            var actions: [ClipInsightAction] = []
            if trimmed != lower { actions.append(ClipInsightAction(title: "Copy lowercase") { lower }) }
            if trimmed != upper { actions.append(ClipInsightAction(title: "Copy uppercase") { upper }) }
            return ClipInsight(kind: .uuid, label: "UUID", color: nil, date: nil, actions: actions + extra)
        }
        if let code = detectCode(text) {
            return ClipInsight(kind: .code(code), label: code?.rawValue ?? "Code", color: nil, date: nil, actions: extra)
        }
        if let decoded = base64Decoder(trimmed) {
            return ClipInsight(kind: .base64, label: "Base64", color: nil, date: nil, actions: [ClipInsightAction(title: "Copy Base64-decoded", make: decoded)])
        }
        if !extra.isEmpty {
            return ClipInsight(kind: .urlEncoded, label: "Encoded", color: nil, date: nil, actions: extra)
        }
        return nil
    }

    static func analyzeLink(_ text: String) -> ClipInsight? {
        let extra = percentAction(for: text)
        guard !extra.isEmpty else { return nil }
        return ClipInsight(kind: .urlEncoded, label: "Encoded", color: nil, date: nil, actions: extra)
    }

    // MARK: Percent encoding

    private static func percentAction(for text: String) -> [ClipInsightAction] {
        guard hasPercentEscape(text), let decoded = text.removingPercentEncoding, decoded != text else { return [] }
        return [ClipInsightAction(title: "Copy URL-decoded") { text.removingPercentEncoding ?? text }]
    }

    private static func hasPercentEscape(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count >= 3 else { return false }
        var i = 0
        while i + 2 < bytes.count {
            if bytes[i] == 0x25, isHex(bytes[i + 1]), isHex(bytes[i + 2]) { return true }
            i += 1
        }
        return false
    }

    private static func isHex(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66)
    }

    // MARK: JSON

    private static func jsonActions(_ trimmed: String) -> [ClipInsightAction]? {
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        guard (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil else { return nil }
        var actions: [ClipInsightAction] = []
        actions.append(ClipInsightAction(title: "Copy pretty JSON") { formatJSON(trimmed, pretty: true) ?? trimmed })
        actions.append(ClipInsightAction(title: "Copy minified JSON") { formatJSON(trimmed, pretty: false) ?? trimmed })
        return actions
    }

    static func formatJSON(_ text: String, pretty: Bool) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return nil }
        var out = ""
        writeJSON(object, pretty: pretty, level: 0, into: &out)
        return out
    }

    private static func writeJSON(_ value: Any, pretty: Bool, level: Int, into out: inout String) {
        if let dict = value as? [String: Any] {
            if dict.isEmpty { out += "{}"; return }
            out += "{"
            let keys = dict.keys.sorted()
            for (i, key) in keys.enumerated() {
                if pretty { out += "\n" + String(repeating: "  ", count: level + 1) }
                out += quote(key)
                out += pretty ? ": " : ":"
                writeJSON(dict[key] as Any, pretty: pretty, level: level + 1, into: &out)
                if i < keys.count - 1 { out += "," }
            }
            if pretty { out += "\n" + String(repeating: "  ", count: level) }
            out += "}"
        } else if let array = value as? [Any] {
            if array.isEmpty { out += "[]"; return }
            out += "["
            for (i, element) in array.enumerated() {
                if pretty { out += "\n" + String(repeating: "  ", count: level + 1) }
                writeJSON(element, pretty: pretty, level: level + 1, into: &out)
                if i < array.count - 1 { out += "," }
            }
            if pretty { out += "\n" + String(repeating: "  ", count: level) }
            out += "]"
        } else if let string = value as? String {
            out += quote(string)
        } else if value is NSNull {
            out += "null"
        } else if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                out += number.boolValue ? "true" : "false"
            } else {
                out += number.stringValue
            }
        } else {
            out += "null"
        }
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    // MARK: Colors

    static func parseColor(_ s: String) -> InsightColor? {
        if s.hasPrefix("#") {
            let digits = Array(s.dropFirst())
            guard [3, 6, 8].contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
            func value(_ chars: ArraySlice<Character>) -> Int { Int(String(chars), radix: 16) ?? 0 }
            if digits.count == 3 {
                return InsightColor(red: value(digits[0..<1]) * 17, green: value(digits[1..<2]) * 17, blue: value(digits[2..<3]) * 17, alpha: 1)
            }
            let a = digits.count == 8 ? Double(value(digits[6..<8])) / 255 : 1
            return InsightColor(red: value(digits[0..<2]), green: value(digits[2..<4]), blue: value(digits[4..<6]), alpha: (a * 100).rounded() / 100)
        }
        let lower = s.lowercased()
        guard lower.hasSuffix(")"), let open = lower.firstIndex(of: "(") else { return nil }
        let name = String(lower[lower.startIndex..<open])
        guard ["rgb", "rgba", "hsl", "hsla"].contains(name) else { return nil }
        let inner = lower[lower.index(after: open)..<lower.index(before: lower.endIndex)]
        let parts = inner.split(whereSeparator: { ",/ \t".contains($0) }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        var alpha = 1.0
        if parts.count == 4 {
            guard let a = number(parts[3], percentScale: 1) , a >= 0, a <= 1 else { return nil }
            alpha = a
        }
        if name.hasPrefix("rgb") {
            var channels: [Int] = []
            for part in parts.prefix(3) {
                guard let v = number(part, percentScale: 2.55), v >= 0, v <= 255 else { return nil }
                channels.append(Int(v.rounded()))
            }
            return InsightColor(red: channels[0], green: channels[1], blue: channels[2], alpha: alpha)
        }
        var hueText = parts[0]
        if hueText.hasSuffix("deg") { hueText.removeLast(3) }
        guard let h = Double(hueText), h.isFinite,
              let sat = number(parts[1], percentScale: 1, percentOnlyDivisor: 100), sat >= 0, sat <= 1,
              let light = number(parts[2], percentScale: 1, percentOnlyDivisor: 100), light >= 0, light <= 1 else { return nil }
        let (r, g, b) = hslToRGB(h: h, s: sat, l: light)
        return InsightColor(red: r, green: g, blue: b, alpha: alpha)
    }

    private static func number(_ s: String, percentScale: Double, percentOnlyDivisor: Double? = nil) -> Double? {
        var text = s
        var isPercent = false
        if text.hasSuffix("%") {
            isPercent = true
            text.removeLast()
        }
        guard let v = Double(text), v.isFinite else { return nil }
        if let divisor = percentOnlyDivisor { return (isPercent || v > 1 ? v : v * 100) / divisor }
        if isPercent { return percentScale == 1 ? v / 100 : v * percentScale }
        return v
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Int, Int, Int) {
        var hue = h.truncatingRemainder(dividingBy: 360)
        if hue < 0 { hue += 360 }
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch hue {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (Int(((r + m) * 255).rounded()), Int(((g + m) * 255).rounded()), Int(((b + m) * 255).rounded()))
    }

    // MARK: Timestamps

    private static func timestampSeconds(_ trimmed: String) -> Double? {
        let count = trimmed.utf8.count
        guard count == 10 || count == 13, trimmed.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
              let raw = Double(trimmed) else { return nil }
        let seconds = count == 13 ? raw / 1000 : raw
        guard seconds >= 946_684_800, seconds < 4_102_444_800 else { return nil }
        return seconds
    }

    private static func isoString(_ seconds: Double, fractional: Bool) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func localString(_ seconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func humanString(_ seconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    // MARK: Base64

    private static func base64Decoder(_ trimmed: String) -> (() -> String)? {
        let bytes = Array(trimmed.utf8)
        guard bytes.count >= 16, bytes.count <= 400_000 else { return nil }
        var padding = 0
        var hasStd = false
        var hasURL = false
        var allHex = true
        var allDigits = true
        for (i, b) in bytes.enumerated() {
            switch b {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39:
                break
            case 0x2B, 0x2F:
                hasStd = true
            case 0x2D, 0x5F:
                hasURL = true
            case 0x3D:
                padding += 1
                if i < bytes.count - 2 { return nil }
            default:
                return nil
            }
            if padding > 0 && b != 0x3D { return nil }
            if !isHex(b) { allHex = false }
            if b < 0x30 || b > 0x39 { allDigits = false }
        }
        guard padding <= 2, !(hasStd && hasURL), !allHex, !allDigits else { return nil }
        let bodyCount = bytes.count - padding
        if padding > 0 {
            guard bytes.count % 4 == 0 else { return nil }
        } else {
            guard bodyCount % 4 != 1 else { return nil }
        }
        guard let decoded = decodeBase64(trimmed), isPrintableText(decoded) else { return nil }
        return { decodeBase64(trimmed) ?? trimmed }
    }

    private static func decodeBase64(_ s: String) -> String? {
        var std = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while std.count % 4 != 0 { std += "=" }
        guard let data = Data(base64Encoded: std), data.count >= 4,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    private static func isPrintableText(_ s: String) -> Bool {
        var total = 0
        var good = 0
        var hasAlnum = false
        for scalar in s.unicodeScalars.prefix(4096) {
            total += 1
            if scalar.value == 0xFFFD { return false }
            if scalar.value >= 0x20 && scalar.value != 0x7F || scalar == "\n" || scalar == "\r" || scalar == "\t" {
                good += 1
            }
            if scalar.properties.isAlphabetic || scalar.properties.numericType != nil { hasAlnum = true }
        }
        return total > 0 && hasAlnum && Double(good) / Double(total) >= 0.97
    }

    // MARK: Code language

    private struct Rule {
        let regex: NSRegularExpression?
        let weight: Double
        let cap: Int

        init(_ pattern: String, _ weight: Double, cap: Int = 3, ci: Bool = false) {
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if ci { options.insert(.caseInsensitive) }
            regex = try? NSRegularExpression(pattern: pattern, options: options)
            self.weight = weight
            self.cap = cap
        }

        func score(_ text: String, range: NSRange) -> Double {
            guard let regex else { return 0 }
            let n = regex.numberOfMatches(in: text, range: range)
            return Double(min(n, cap)) * weight
        }
    }

    private static let swiftRules = [
        Rule(#"\bfunc\s+\w+"#, 3), Rule(#"^\s*import\s+(Foundation|SwiftUI|UIKit|AppKit|Combine|XCTest)\b"#, 7),
        Rule(#"\bguard\s+[^\n]*\belse\b"#, 4), Rule(#"\bstruct\s+\w+\s*:\s*\w+"#, 4),
        Rule(#"@(State|Binding|Published|ObservedObject|MainActor|Environment|StateObject|Observable)\b"#, 5),
        Rule(#"\bif\s+let\b"#, 4), Rule(#"\bsome\s+View\b"#, 7), Rule(#"\bextension\s+\w+"#, 3),
        Rule(#"\b(let|var)\s+\w+\s*:\s*\[?[A-Z]\w*\]?\??\s*(=|$)"#, 2), Rule(#"\)\s*->\s*\w+"#, 3), Rule(#"\bfunc\s+\w+\(_\s"#, 3),
        Rule(#"\b(private|fileprivate|public|internal)\s+(func|var|let|struct|class|enum)\b"#, 2),
        Rule(#"\bnil\b"#, 1, cap: 2), Rule(#"\bprint\("#, 1, cap: 1)
    ]

    private static let jsRules = [
        Rule(#"\bconst\s+\w+\s*="#, 2), Rule(#"=>"#, 2), Rule(#"\bfunction\s*\w*\s*\("#, 3),
        Rule(#"\bimport\s+[^\n]*\sfrom\s+['"]"#, 6), Rule(#"\bexport\s+(default|const|function|class|async)\b"#, 4),
        Rule(#"console\.\w+\("#, 4), Rule(#"\brequire\(['"]"#, 4), Rule(#"===|!=="#, 2),
        Rule(#"\blet\s+\w+\s*="#, 1), Rule(#"\b(await|async)\b"#, 2), Rule(#"\bdocument\.\w+"#, 3),
        Rule(#"\bmodule\.exports\b"#, 4), Rule(#"\bnull\b|\bundefined\b"#, 1, cap: 2)
    ]

    private static let tsRules = [
        Rule(#"\binterface\s+\w+\s*(<[^>]*>)?\s*(extends\s+[\w, ]+)?\{"#, 5),
        Rule(#"[\w)\]]\s*:\s*(string|number|boolean|any|void|unknown|never)\b"#, 4),
        Rule(#"\btype\s+\w+(<[^>]*>)?\s*="#, 4), Rule(#"\bas\s+(string|number|any|const|unknown)\b"#, 3),
        Rule(#"\b(Promise|Array|Record|Partial)<"#, 3), Rule(#"\bexport\s+(interface|type|enum)\b"#, 4)
    ]

    private static let pythonRules = [
        Rule(#"^\s*def\s+\w+\s*\([^\n]*\)\s*(->[^\n]*)?:\s*$"#, 6), Rule(#"^\s*class\s+\w+(\([^\n]*\))?:\s*$"#, 5),
        Rule(#"^\s*from\s+[\w.]+\s+import\b"#, 5), Rule(#"^\s*import\s+\w+(\s+as\s+\w+)?\s*$"#, 2),
        Rule(#"\bself\b"#, 2), Rule(#"^\s*elif\b[^\n]*:\s*$"#, 4),
        Rule(#"^\s*(if|else|for|while|try|except|finally|with)\b[^\n]*:\s*$"#, 3),
        Rule(#"\b(None|True|False)\b"#, 2), Rule(#"__\w+__"#, 3), Rule(#"^\s*@\w+"#, 1),
        Rule(#"\bprint\("#, 1, cap: 1), Rule(#"\bf["'][^"'\n]*\{"#, 2), Rule(#"\bdef\s+\w+"#, 2)
    ]

    private static let goRules = [
        Rule(#"^package\s+\w+\s*$"#, 7), Rule(#"\bfunc\s+(\(\w+\s+\*?\w+\)\s*)?\w+\([^)\n]*\)(?!\s*->)"#, 5),
        Rule(#":="#, 3), Rule(#"\bfmt\.\w+\("#, 5), Rule(#"^import\s+\("#, 5),
        Rule(#"\bdefer\b|\bgo\s+func\b|\bchan\b"#, 3), Rule(#"\berr\s*!=\s*nil"#, 6),
        Rule(#"\btype\s+\w+\s+(struct|interface)\b"#, 5), Rule(#"\bmake\(|\bappend\("#, 2),
        Rule(#"\bfunc\s+\w+\([^)]*\)\s+(\(?[\w*,\s\[\]]+\)?)\s*\{"#, 2)
    ]

    private static let rustRules = [
        Rule(#"\bfn\s+\w+"#, 5), Rule(#"\blet\s+mut\b"#, 6), Rule(#"\bimpl(\s*<[^>]*>)?\s+\w+"#, 4),
        Rule(#"^\s*use\s+[\w:]+::"#, 6), Rule(#"\b(println|print|format|vec|panic|assert_eq|assert)!\s*[(\[]"#, 6),
        Rule(#"\bpub\s+(fn|struct|enum|mod|trait)\b"#, 5), Rule(#"&mut\b|&'\w+"#, 3),
        Rule(#"#\[derive"#, 6), Rule(#"\bunwrap\(\)|\.expect\("#, 3), Rule(#"\b(Option|Result|Vec|Box)<"#, 3),
        Rule(#"->\s*(Result|Option|Self)\b"#, 3), Rule(#"\bmatch\s+[^\n{]+\{"#, 2)
    ]

    private static let sqlRules = [
        Rule(#"\bSELECT\b[\s\S]{0,400}?\bFROM\b"#, 6), Rule(#"\bINSERT\s+INTO\b"#, 6),
        Rule(#"\bUPDATE\s+\w+\s+SET\b"#, 6), Rule(#"\bDELETE\s+FROM\b"#, 6),
        Rule(#"\bCREATE\s+(TABLE|INDEX|VIEW|UNIQUE)\b"#, 6), Rule(#"\bALTER\s+TABLE\b"#, 6),
        Rule(#"\bDROP\s+(TABLE|INDEX|VIEW)\b"#, 6),
        Rule(#"\bWHERE\b"#, 2), Rule(#"\b(INNER|LEFT|RIGHT|FULL|CROSS)?\s*JOIN\b"#, 2),
        Rule(#"\bGROUP\s+BY\b|\bORDER\s+BY\b"#, 3),
        Rule(#"\bselect\s+[\w*.,()\s]+?\s+from\s+\w+"#, 3, ci: true),
        Rule(#"\binsert\s+into\s+\w+"#, 3, ci: true), Rule(#"\bwhere\s+\w+\s*(=|<|>|like|in)\b"#, 2, ci: true)
    ]

    private static let shellRules = [
        Rule(#"^#!\s*/(usr/)?bin/(env\s+)?(ba|z|da)?sh\b"#, 10),
        Rule(#"^\s*(sudo|brew|npm|npx|yarn|pnpm|git|cd|ls|cat|grep|curl|wget|echo|export|chmod|mkdir|rm|mv|cp|docker|kubectl|pip|pip3|apt|apt-get|xcodebuild|swift|cargo|make|ssh|scp|tar|source|kill|open)\s"#, 3),
        Rule(#"^\$\s+\S+"#, 4), Rule(#"\|\s*(grep|awk|sed|xargs|head|tail|sort|wc|uniq|tee|jq)\b"#, 3),
        Rule(#"\$\{?\w+\}?"#, 1), Rule(#"^\s*(fi|done|esac)\s*$"#, 3),
        Rule(#"^\s*if\s+\[\[?\s"#, 4), Rule(#"2>&1|>\s*/dev/null"#, 4), Rule(#"\s&&\s"#, 1),
        Rule(#"^\s*(for|while)\s+\w+\s+in\b[^\n]*;\s*do\b"#, 4), Rule(#"\s--[a-z][a-z-]+"#, 1)
    ]

    private static let htmlRules = [
        Rule(#"<!DOCTYPE\s+html"#, 10, ci: true),
        Rule(#"</?(div|span|html|head|body|p|a|ul|ol|li|script|style|h[1-6]|img|section|button|form|input|meta|link|title|table|tr|td|nav|header|footer|main|label|select|option)\b[^>]*>"#, 2, ci: true),
        Rule(#"<\w+[^>\n]*/>"#, 1), Rule(#"\bclass="[^"]*""#, 2), Rule(#"</\w+>"#, 1.5)
    ]

    private static let cssRules = [
        Rule(#"^[ \t]*[.#]?[\w\-:\s,>.#\[\]="'*+~()]+\{[ \t]*$"#, 2),
        Rule(#"^[ \t]*[a-z-]+[ \t]*:[ \t]*[^;{}\n]+;[ \t]*$"#, 2),
        Rule(#"@(media|import|font-face|keyframes|supports)\b"#, 4), Rule(#"\b\d+(px|rem|em|vh|vw)\b"#, 2),
        Rule(#"#[0-9a-fA-F]{3,8}\b"#, 1), Rule(#"!important"#, 3),
        Rule(#"\b(display|margin|padding|color|background|font-size|border|width|height|flex)\s*:"#, 2)
    ]

    private static func yamlScore(_ sample: String) -> Double {
        if sample.contains(";") && sample.contains("{") { return 0 }
        let lines = sample.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.count >= 2 else { return 0 }
        guard let keyRule = yamlKey, let listRule = yamlList else { return 0 }
        var keys = 0
        var items = 0
        var marker = 0
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if line == "---" { marker += 1 }
            else if keyRule.firstMatch(in: line, range: range) != nil { keys += 1 }
            else if listRule.firstMatch(in: line, range: range) != nil { items += 1 }
        }
        guard keys >= 2, Double(keys + items + marker) / Double(lines.count) >= 0.7 else { return 0 }
        return Double(min(keys, 8)) * 2 + Double(min(items, 4)) + (marker > 0 ? 4 : 0)
    }

    private static let yamlKey = try? NSRegularExpression(pattern: #"^[\w.\-"']+:(?:\s+[^;{}]*[^;{},\s])?\s*$"#)
    private static let yamlList = try? NSRegularExpression(pattern: #"^-\s+\S"#)

    static var invalidRuleCount: Int {
        let all = swiftRules + jsRules + tsRules + pythonRules + goRules + rustRules + sqlRules + shellRules + htmlRules + cssRules
        return all.filter { $0.regex == nil }.count + (yamlKey == nil ? 1 : 0) + (yamlList == nil ? 1 : 0)
    }

    static func codeScores(_ text: String) -> [(CodeLanguage, Double)] {
        let sample = String(text.prefix(maxCodeSample))
        let range = NSRange(sample.startIndex..., in: sample)
        func total(_ rules: [Rule]) -> Double { rules.reduce(0) { $0 + $1.score(sample, range: range) } }
        let ts = total(tsRules)
        let js = total(jsRules) + ts
        return [
            (.swift, total(swiftRules)),
            (ts >= 4 ? .typescript : .javascript, js),
            (.python, total(pythonRules)),
            (.go, total(goRules)),
            (.rust, total(rustRules)),
            (.sql, total(sqlRules)),
            (.shell, total(shellRules)),
            (.html, total(htmlRules)),
            (.css, total(cssRules)),
            (.yaml, yamlScore(sample))
        ]
    }

    static func detectCode(_ text: String) -> CodeLanguage?? {
        let looks = ClipClassifier.looksLikeCode(text)
        let sample = text.prefix(maxCodeSample)
        let nonEmptyLines = sample.split(separator: "\n", omittingEmptySubsequences: true).count
        let multiline = nonEmptyLines >= 3
        guard looks || multiline else { return nil }
        var best: (CodeLanguage, Double)?
        for entry in codeScores(text) where entry.1 > (best?.1 ?? 0) { best = entry }
        let threshold = looks ? 3.0 : 6.0
        if let best, best.1 >= threshold { return .some(best.0) }
        if looks && nonEmptyLines >= 2 { return .some(nil) }
        return nil
    }
}
