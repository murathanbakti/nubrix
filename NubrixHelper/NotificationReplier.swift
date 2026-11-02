import AppKit
import ApplicationServices
import CoreGraphics
import os

private let replyLog = Logger(subsystem: "dev.nubrix.app", category: "reply")

enum NotificationReplyStatus: String {
    case sent
    case notFound
    case noAccess
    case unsupported
    case failed
    case unconfirmed
    case gone
    case previewsHidden

    func encoded() -> Data {
        (try? JSONSerialization.data(withJSONObject: ["status": rawValue])) ?? Data()
    }
}

final class NotificationReplier {
    static let shared = NotificationReplier()

    private static let timeout: TimeInterval = 9
    private static let maxRequestBytes = 16 * 1024
    private let queue = DispatchQueue(label: "dev.nubrix.helper.notificationReply", qos: .userInitiated)
    private let flightLock = NSLock()
    private var inFlight = false

    private init() {}

    private func claim() -> Bool {
        flightLock.lock()
        defer { flightLock.unlock() }
        if inFlight { return false }
        inFlight = true
        return true
    }

    private func release() {
        flightLock.lock()
        inFlight = false
        flightLock.unlock()
    }

    func reply(_ data: Data, completion: @escaping (Data) -> Void) {
        let job = ReplyJob(deadline: Date().addingTimeInterval(Self.timeout), completion: completion)
        guard data.count <= Self.maxRequestBytes, let request = ReplyRequest.parse(data), claim() else {
            job.finish(.failed)
            return
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.timeout) {
            job.finish(job.isSubmitted ? .unconfirmed : .failed)
        }
        queue.async {
            let status = ReplySession(job: job, request: request).run()
            job.finish(status)
            self.release()
        }
    }
}

private final class ReplyJob: @unchecked Sendable {
    let deadline: Date
    private let startedAt = Date()
    private let completion: (Data) -> Void
    private let lock = NSLock()
    private var finished = false
    private var submitted = false

    init(deadline: Date, completion: @escaping (Data) -> Void) {
        self.deadline = deadline
        self.completion = completion
    }

    var isExpired: Bool { Date() >= deadline }

    var isSubmitted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return submitted
    }

    func beginSubmit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if finished { return false }
        submitted = true
        return true
    }

    func finish(_ status: NotificationReplyStatus) {
        lock.lock()
        let already = finished
        finished = true
        lock.unlock()
        if !already {
            let elapsed = Int(Date().timeIntervalSince(startedAt) * 1000)
            replyLog.info("reply summary status=\(status.rawValue, privacy: .public) elapsedMs=\(elapsed, privacy: .public)")
            completion(status.encoded())
        }
    }
}

private struct ReplyRequest {
    let appName: String
    let title: String
    let body: String
    let subtitle: String
    let text: String
    let recID: Int64?
    let bundleID: String

    private struct Raw: Decodable {
        var recID: Int64?
        var bundleID: String?
        var appName: String?
        var title: String?
        var body: String?
        var subtitle: String?
        var text: String?
    }

    static func parse(_ data: Data) -> ReplyRequest? {
        guard let raw = try? JSONDecoder().decode(Raw.self, from: data) else { return nil }
        let text = (raw.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 2000 else { return nil }
        let title = String((raw.title ?? "").prefix(500))
        let body = String((raw.body ?? "").prefix(500))
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ReplyRequest(appName: String((raw.appName ?? "").prefix(500)), title: title, body: body, subtitle: String((raw.subtitle ?? "").prefix(500)), text: text, recID: raw.recID, bundleID: String((raw.bundleID ?? "").prefix(500)))
    }
}

private struct TextPart {
    let source: String
    let text: String
}

private struct OwnedPart {
    let part: TextPart
    let owner: Int
}

private struct AXNode {
    let element: AXUIElement
    let parent: Int
    let depth: Int
    let role: String
    let subrole: String
    var customActions: [String]
    var parts: [TextPart]

    var isCandidate: Bool { subrole.hasPrefix("AXNotificationCenter") || !customActions.isEmpty }
}

private struct NotificationMatch {
    let element: AXUIElement
    let actions: [String]
    let subrole: String
}

private enum LocateResult {
    case found(NotificationMatch)
    case missing
    case blocked
}

private final class ReplySession {
    private static let ncBundleID = "com.apple.notificationcenterui"
    private static let controlCenterBundleID = "com.apple.controlcenter"
    private static let maxNodes = 3000
    private static let maxDepth = 25
    private static let messagingTimeout: Float = 1
    private static let pollInterval: TimeInterval = 0.25
    private static let pollWindow: TimeInterval = 2.5
    private static let maxCandidateLogs = 30
    private static let partRoles: Set<String> = ["AXStaticText", "AXGroup", "AXButton", "AXTextArea"]

    private static let replyWords = [
        "reply", "yanıtla", "cevapla", "yanıt", "antworten", "répondre", "responder", "rispondi", "beantwoorden",
        "svara", "svar", "odpowiedz", "ответить", "回复", "回覆", "返信", "답장"
    ]

    private static let sendWords = [
        "send", "gönder", "senden", "envoyer", "enviar", "invia", "verzenden", "skicka", "wyślij", "отправить",
        "发送", "傳送", "送信", "보내기"
    ]

    private static let editableRoles: Set<String> = ["AXTextField", "AXTextArea"]
    private static let textlessRoles: Set<String> = ["AXStaticText", "AXImage", "AXTextField", "AXTextArea"]

    private let job: ReplyJob
    private let request: ReplyRequest
    private var ncPid: pid_t = 0
    private var openedNotificationCenter = false
    private var previewsHidden = false

    init(job: ReplyJob, request: ReplyRequest) {
        self.job = job
        self.request = request
    }

    func run() -> NotificationReplyStatus {
        if let recID = request.recID {
            let present = SystemNotificationReader().exists(recID: recID)
            replyLog.info("reply exists known=\(present != nil, privacy: .public) present=\(present ?? false, privacy: .public)")
            if present == false { return .gone }
        }
        guard AXIsProcessTrusted() else { return .noAccess }
        guard let pid = Self.pid(of: Self.ncBundleID) else { return .notFound }
        ncPid = pid
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        defer { closeNotificationCenterIfOpened() }

        replyLog.info("reply request titleLen=\(Self.normalize(self.request.title).count, privacy: .public) bodyLen=\(Self.normalize(self.request.body).count, privacy: .public) appLen=\(Self.normalize(self.request.appName).count, privacy: .public) textLen=\(self.request.text.count, privacy: .public)")

        switch locate(app, pass: "initial") {
        case .found(let match):
            return perform(match, app: app)
        case .blocked:
            return missingStatus()
        case .missing:
            break
        }

        guard !job.isExpired else { return missingStatus() }
        let opened = openNotificationCenter(app)
        replyLog.info("reply openNotificationCenter opened=\(opened, privacy: .public)")
        guard opened else { return missingStatus() }

        let pollEnd = min(Date().addingTimeInterval(Self.pollWindow), job.deadline)
        var attempt = 1
        while true {
            switch locate(app, pass: "afterOpen#\(attempt)") {
            case .found(let match):
                return perform(match, app: app)
            case .blocked:
                return missingStatus()
            case .missing:
                break
            }
            guard Date().addingTimeInterval(Self.pollInterval) < pollEnd, !job.isExpired else { break }
            Thread.sleep(forTimeInterval: Self.pollInterval)
            attempt += 1
        }
        return missingStatus()
    }

    private func missingStatus() -> NotificationReplyStatus {
        replyLog.info("reply previewsHidden=\(self.previewsHidden, privacy: .public)")
        return previewsHidden ? .previewsHidden : .notFound
    }

    private static func pid(of bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private func elements(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        (attribute(element, name) as? [AXUIElement]) ?? []
    }

    private func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func actionNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    private func customActions(_ element: AXUIElement) -> [String] {
        actionNames(element).filter { $0.hasPrefix("Name:") }
    }

    private static func displayName(of action: String) -> String {
        var name = action
        if name.hasPrefix("Name:") { name.removeFirst(5) }
        if let end = name.firstIndex(where: { $0.isNewline }) { name = String(name[..<end]) }
        return name
    }

    private static func normalize(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x2069, 0xFEFF, 0x00AD, 0xFE00...0xFE0F:
                continue
            case 0x00A0, 0x202F:
                scalars.append(" ")
            default:
                if scalar.properties.generalCategory == .control, !scalar.properties.isWhitespace { continue }
                scalars.append(scalar)
            }
        }
        return String(scalars)
            .precomposedStringWithCanonicalMapping
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func tokens(_ normalized: String) -> [String] {
        normalized.split(separator: " ").map(String.init)
    }

    private func makeNode(_ element: AXUIElement, parent: Int, depth: Int, gatherParts: Bool) -> AXNode {
        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        var parts: [TextPart] = []
        if gatherParts, Self.partRoles.contains(role) {
            for name in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute] {
                if let text = string(element, name), !text.isEmpty { parts.append(TextPart(source: "\(role).\(name)", text: text)) }
            }
        }
        var actions: [String] = []
        if gatherParts, !Self.textlessRoles.contains(role) {
            actions = customActions(element)
        }
        return AXNode(element: element, parent: parent, depth: depth, role: role, subrole: subrole,
                      customActions: actions, parts: parts)
    }

    private func collect(roots: [AXUIElement], maxNodes: Int, maxDepth: Int, gatherParts: Bool) -> [AXNode] {
        var nodes: [AXNode] = []
        for root in roots.prefix(maxNodes) {
            nodes.append(makeNode(root, parent: -1, depth: 0, gatherParts: gatherParts))
        }
        var cursor = 0
        while cursor < nodes.count, nodes.count < maxNodes, !job.isExpired {
            let node = nodes[cursor]
            if node.depth < maxDepth {
                for child in elements(node.element, kAXChildrenAttribute) {
                    if nodes.count >= maxNodes { break }
                    nodes.append(makeNode(child, parent: cursor, depth: node.depth + 1, gatherParts: gatherParts))
                }
            }
            cursor += 1
        }
        return nodes
    }

    private func frameSize(_ element: AXUIElement) -> String {
        guard let value = attribute(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return "?" }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size) else { return "?" }
        return "\(Int(size.width))x\(Int(size.height))"
    }

    private func ancestorSummary(_ nodes: [AXNode], from index: Int) -> String {
        var parts: [String] = []
        var ancestor = nodes[index].parent
        while ancestor >= 0, parts.count < 3 {
            parts.append("\(nodes[ancestor].role)/\(nodes[ancestor].subrole)")
            ancestor = nodes[ancestor].parent
        }
        return parts.joined(separator: ",")
    }

    private func locate(_ app: AXUIElement, pass: String) -> LocateResult {
        let windows = elements(app, kAXWindowsAttribute)
        for (index, window) in windows.enumerated() {
            let role = string(window, kAXRoleAttribute) ?? ""
            let subrole = string(window, kAXSubroleAttribute) ?? ""
            let children = elements(window, kAXChildrenAttribute).count
            let size = frameSize(window)
            replyLog.info("locate pass=\(pass, privacy: .public) window=\(index, privacy: .public) role=\(role, privacy: .public) subrole=\(subrole, privacy: .public) children=\(children, privacy: .public) size=\(size, privacy: .public)")
        }
        guard !windows.isEmpty else {
            replyLog.info("locate pass=\(pass, privacy: .public) windows=0 nodes=0 candidates=0 matches=0 result=missing reason=noWindows")
            return .missing
        }
        let nodes = collect(roots: windows, maxNodes: Self.maxNodes, maxDepth: Self.maxDepth, gatherParts: true)
        guard !job.isExpired else {
            replyLog.info("locate pass=\(pass, privacy: .public) windows=\(windows.count, privacy: .public) nodes=\(nodes.count, privacy: .public) candidates=0 matches=0 result=missing reason=expired")
            return .missing
        }

        var texts = [[OwnedPart]](repeating: [], count: nodes.count)
        for (index, node) in nodes.enumerated() where node.isCandidate {
            for name in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute] {
                if let text = string(node.element, name), !text.isEmpty {
                    texts[index].append(OwnedPart(part: TextPart(source: "self.\(name)", text: text), owner: index))
                }
            }
        }
        for node in nodes where !node.parts.isEmpty && !node.isCandidate {
            var ancestor = node.parent
            var distance = 1
            while ancestor >= 0, distance <= 10 {
                if nodes[ancestor].isCandidate {
                    texts[ancestor].append(contentsOf: node.parts.map { OwnedPart(part: $0, owner: ancestor) })
                    break
                }
                ancestor = nodes[ancestor].parent
                distance += 1
            }
        }

        let title = Self.normalize(request.title)
        let subtitle = Self.normalize(request.subtitle)
        let body = Self.normalize(request.body)
        let appName = Self.normalize(request.appName)

        struct Evaluation {
            var app = false
            var sender = false
            var message = false
            var distinct = false
            var ownParts = false
            var appIndex: Int?
            var base: Bool { app && sender && message && distinct && ownParts }
        }

        var candidates: [Int] = []
        var evaluations: [Int: Evaluation] = [:]
        var normalizedParts: [Int: [String]] = [:]
        for (index, node) in nodes.enumerated() where node.isCandidate {
            candidates.append(index)
            let owned = texts[index]
            let norm = owned.map { Self.normalize($0.part.text) }
            normalizedParts[index] = norm
            var evaluation = Evaluation()
            if !appName.isEmpty { evaluation.appIndex = norm.firstIndex(of: appName) }
            evaluation.app = evaluation.appIndex != nil
            let titleIndexes = norm.indices.filter { !title.isEmpty && norm[$0] == title }
            evaluation.sender = !titleIndexes.isEmpty && (subtitle.isEmpty || norm.contains(subtitle))
            let bodyIndexes = norm.indices.filter {
                let result = Self.bodyMatch(norm[$0], body: body)
                return result.exact || result.prefix
            }
            evaluation.message = !bodyIndexes.isEmpty
            let pairs = titleIndexes.flatMap { t in bodyIndexes.filter { $0 != t }.map { (t, $0) } }
            evaluation.distinct = !pairs.isEmpty
            evaluation.ownParts = pairs.contains { owned[$0.0].owner == index && owned[$0.1].owner == index }
            evaluations[index] = evaluation
        }

        func deduped(_ indexes: [Int]) -> [Int] {
            var unique: [Int] = []
            for index in indexes where !unique.contains(where: { CFEqual(nodes[$0].element, nodes[index].element) }) {
                unique.append(index)
            }
            return unique
        }

        let baseMatches = deduped(candidates.filter { evaluations[$0]?.base == true })

        func isStack(_ index: Int) -> Bool { nodes[index].subrole.contains("Stack") }

        func stackReason(_ index: Int) -> String {
            guard baseMatches.count == 1 else { return "stackNotUnique" }
            guard texts[index].count <= 6 else { return "tooManyParts" }
            guard let norm = normalizedParts[index], let appIndex = evaluations[index]?.appIndex else { return "noApp" }
            let after = norm.indices.filter { $0 > appIndex && !norm[$0].isEmpty && norm[$0] != appName }
            guard let first = after.first, norm[first] == title else { return "titleNotFirst" }
            let rest = after.filter { norm[$0] != title && (subtitle.isEmpty || norm[$0] != subtitle) }
            guard let next = rest.first else { return "bodyNotNext" }
            let nextMatch = Self.bodyMatch(norm[next], body: body)
            guard nextMatch.exact || nextMatch.prefix else { return "bodyNotNext" }
            var known: Set<String> = [appName, title, subtitle]
            for word in Self.replyWords + Self.sendWords { known.insert(Self.normalize(word)) }
            for word in Self.closeWords.union(Self.clearAllWords) { known.insert(Self.normalize(word)) }
            for action in nodes[index].customActions { known.insert(Self.normalize(Self.displayName(of: action))) }
            for text in norm where !text.isEmpty && !known.contains(text) {
                let match = Self.bodyMatch(text, body: body)
                if !(match.exact || match.prefix) { return "otherText" }
            }
            return "ok"
        }

        var accepted: [Int] = []
        var reasons: [Int: String] = [:]
        for index in candidates {
            guard let evaluation = evaluations[index] else { continue }
            if accepted.contains(where: { CFEqual(nodes[$0].element, nodes[index].element) }) {
                reasons[index] = "sameElement"
                continue
            }
            let reason: String
            if !evaluation.app {
                reason = "noApp"
            } else if !evaluation.sender {
                reason = "noSender"
            } else if !evaluation.message {
                reason = "noMessage"
            } else if !evaluation.distinct {
                reason = "notDistinct"
            } else if !evaluation.ownParts {
                reason = "notOwnParts"
            } else if isStack(index) {
                reason = stackReason(index)
            } else {
                reason = "ok"
            }
            reasons[index] = reason
            if reason == "ok" { accepted.append(index) }
        }
        if accepted.count > 1 {
            for index in accepted { reasons[index] = "duplicate" }
        }

        var anyTitle = false
        var anyBody = false
        for index in candidates {
            for text in normalizedParts[index] ?? [] {
                if !title.isEmpty, text.contains(title) { anyTitle = true }
                if !body.isEmpty, text.contains(body) { anyBody = true }
            }
        }
        let hasReplyCandidate = candidates.contains { nodes[$0].customActions.contains(where: isReplyAction) }
        previewsHidden = accepted.isEmpty && hasReplyCandidate && !anyTitle && !anyBody && !(title.isEmpty && body.isEmpty)

        for (position, index) in candidates.enumerated() where position < Self.maxCandidateLogs {
            let node = nodes[index]
            let identifier = string(node.element, kAXIdentifierAttribute) ?? ""
            let roleDescription = string(node.element, kAXRoleDescriptionAttribute) ?? ""
            let childCount = elements(node.element, kAXChildrenAttribute).count
            let actionNames = node.customActions.map { Self.displayName(of: $0) }.joined(separator: "|")
            let ancestors = ancestorSummary(nodes, from: index)
            replyLog.info("cand pass=\(pass, privacy: .public) i=\(index, privacy: .public) depth=\(node.depth, privacy: .public) role=\(node.role, privacy: .public) subrole=\(node.subrole, privacy: .public) id=\(identifier, privacy: .private) actions=[\(actionNames, privacy: .private)] parts=\(texts[index].count, privacy: .public) roleDesc=\(roleDescription, privacy: .private) hasChildren=\(childCount > 0, privacy: .public) children=\(childCount, privacy: .public) anc=[\(ancestors, privacy: .public)]")
            for (k, owned) in texts[index].enumerated() {
                let normalized = normalizedParts[index]?[k] ?? ""
                let bodyResult = Self.bodyMatch(normalized, body: body)
                let eqApp = !appName.isEmpty && normalized == appName
                let eqTitle = !title.isEmpty && normalized == title
                let eqSubtitle = !subtitle.isEmpty && normalized == subtitle
                let hasApp = !appName.isEmpty && normalized.contains(appName)
                let hasTitle = !title.isEmpty && normalized.contains(title)
                let hasBody = !body.isEmpty && normalized.contains(body)
                replyLog.info("part pass=\(pass, privacy: .public) cand=\(index, privacy: .public) k=\(k, privacy: .public) src=\(owned.part.source, privacy: .public) len=\(normalized.count, privacy: .public) words=\(Self.tokens(normalized).count, privacy: .public) eqApp=\(eqApp, privacy: .public) eqTitle=\(eqTitle, privacy: .public) eqSubtitle=\(eqSubtitle, privacy: .public) bodyExact=\(bodyResult.exact, privacy: .public) bodyPrefix=\(bodyResult.prefix, privacy: .public) hasApp=\(hasApp, privacy: .public) hasTitle=\(hasTitle, privacy: .public) hasBody=\(hasBody, privacy: .public)")
                if owned.part.source == "self.AXDescription" || normalized.count > 60 {
                    let segments = normalized
                        .replacingOccurrences(of: "\n", with: ", ")
                        .components(separatedBy: ", ")
                    for (s, raw) in segments.prefix(20).enumerated() {
                        let segment = raw.trimmingCharacters(in: .whitespaces)
                        let segmentBody = Self.bodyMatch(segment, body: body)
                        let hasDigits = segment.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
                        replyLog.info("seg pass=\(pass, privacy: .public) cand=\(index, privacy: .public) k=\(k, privacy: .public) s=\(s, privacy: .public) len=\(segment.count, privacy: .public) words=\(Self.tokens(segment).count, privacy: .public) eqApp=\(!appName.isEmpty && segment == appName, privacy: .public) eqTitle=\(!title.isEmpty && segment == title, privacy: .public) eqSubtitle=\(!subtitle.isEmpty && segment == subtitle, privacy: .public) bodyExact=\(segmentBody.exact, privacy: .public) bodyPrefix=\(segmentBody.prefix, privacy: .public) hasDigits=\(hasDigits, privacy: .public)")
                    }
                }
            }
            if let evaluation = evaluations[index] {
                replyLog.info("match cand=\(index, privacy: .public) app=\(evaluation.app, privacy: .public) sender=\(evaluation.sender, privacy: .public) message=\(evaluation.message, privacy: .public) distinct=\(evaluation.distinct, privacy: .public) ownParts=\(evaluation.ownParts, privacy: .public) accepted=\(reasons[index] == "ok", privacy: .public) reason=\(reasons[index] ?? "none", privacy: .public)")
            }
        }

        func finish(_ result: LocateResult, _ label: String) -> LocateResult {
            replyLog.info("locate pass=\(pass, privacy: .public) windows=\(windows.count, privacy: .public) nodes=\(nodes.count, privacy: .public) candidates=\(candidates.count, privacy: .public) matches=\(baseMatches.count, privacy: .public) accepted=\(accepted.count, privacy: .public) result=\(label, privacy: .public)")
            return result
        }

        guard !baseMatches.isEmpty else { return finish(.missing, "missing") }
        guard accepted.count == 1, let chosen = accepted.first else { return finish(.blocked, "blocked reason=\(accepted.isEmpty ? "rejected" : "duplicate")") }

        let node = nodes[chosen]
        return finish(.found(NotificationMatch(element: node.element, actions: node.customActions, subrole: node.subrole)), "found")
    }

    private static func bodyMatch(_ part: String, body: String) -> (exact: Bool, prefix: Bool) {
        guard !body.isEmpty, !part.isEmpty else { return (false, false) }
        if part == body { return (true, false) }
        for mark in ["…", "..."] where part.hasSuffix(mark) {
            let stem = String(part.dropLast(mark.count)).trimmingCharacters(in: .whitespaces)
            if stem.count >= 12, body.hasPrefix(stem) { return (false, true) }
        }
        return (false, false)
    }

    private func isReplyAction(_ action: String) -> Bool {
        let name = Self.normalize(Self.displayName(of: action))
        guard !name.isEmpty else { return false }
        return Self.replyWords.contains(name)
    }

    private func perform(_ match: NotificationMatch, app: AXUIElement) -> NotificationReplyStatus {
        let names = match.actions.map { Self.displayName(of: $0) }.joined(separator: "|")
        let replyAction = match.actions.first(where: isReplyAction)
        replyLog.info("perform replyActionFound=\(replyAction != nil, privacy: .public) actions=[\(names, privacy: .private)]")
        guard let action = replyAction else { return .unsupported }
        guard !job.isExpired else { return .failed }
        let pressed = AXUIElementPerformAction(match.element, action as CFString) == .success
        replyLog.info("perform actionPressed=\(pressed, privacy: .public)")
        guard pressed else { return .failed }

        let field = awaitTextField(notification: match.element, app: app)
        replyLog.info("perform textFieldFound=\(field != nil, privacy: .public)")
        guard let field else { return .failed }
        let applied = !job.isExpired && setText(field)
        replyLog.info("perform setAndReadback=\(applied, privacy: .public)")
        guard applied else {
            _ = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFString)
            return .failed
        }
        guard !job.isExpired else {
            _ = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFString)
            return .failed
        }

        guard job.beginSubmit() else {
            _ = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFString)
            return .failed
        }
        let path = submit(field: field, notification: match.element)
        let sent = awaitSent(field, viaAction: path != "return")
        replyLog.info("perform submitPath=\(path, privacy: .public) confirmed=\(sent, privacy: .public)")
        if sent { cleanup(match) }
        return sent ? .sent : .unconfirmed
    }

    private static let closeWords: Set<String> = [
        "close", "clear", "kapat", "temizle", "schließen", "löschen", "fermer", "effacer", "cerrar", "borrar",
        "chiudi", "cancella", "sluiten", "wissen", "stäng", "rensa", "zamknij", "wyczyść", "закрыть", "очистить",
        "关闭", "清除", "關閉", "閉じる", "消去", "닫기", "지우기"
    ]

    private static let clearAllWords: Set<String> = [
        "clear all", "tümünü temizle", "alle löschen", "tout effacer", "borrar todo", "cancella tutto",
        "alles wissen", "rensa alla", "wyczyść wszystko", "очистить все", "全部清除", "すべて消去", "모두 지우기"
    ]

    private func cleanup(_ match: NotificationMatch) {
        func log(_ removed: Bool, _ action: String, _ skipped: String) {
            replyLog.info("cleanup removedByMac=\(removed, privacy: .public) action=\(action, privacy: .public) skipped=\(skipped, privacy: .public)")
        }
        let reader = SystemNotificationReader()
        if let recID = request.recID {
            let limit = min(Date().addingTimeInterval(1), job.deadline)
            repeat {
                if reader.exists(recID: recID) == false {
                    log(true, "none", "none")
                    return
                }
                Thread.sleep(forTimeInterval: 0.15)
            } while Date() < limit
        }
        guard !job.isExpired else { return log(false, "none", "deadline") }
        let isStack = match.subrole.contains("Stack")
        let wanted = isStack ? Self.clearAllWords : Self.closeWords
        guard let action = match.actions.first(where: { wanted.contains(Self.normalize(Self.displayName(of: $0))) }) else {
            return log(false, "none", "noAction")
        }
        if isStack {
            guard !request.bundleID.isEmpty, let count = reader.recordCount(bundleID: request.bundleID) else {
                return log(false, "none", "countUnknown")
            }
            guard count == 1 else { return log(false, "none", "multipleRecords") }
        }
        let pressed = AXUIElementPerformAction(match.element, action as CFString) == .success
        log(false, pressed ? (isStack ? "clearAll" : "close") : "none", pressed ? "none" : "actionFailed")
    }

    private func isEditable(_ node: AXNode) -> Bool {
        guard Self.editableRoles.contains(node.role) else { return false }
        if let enabled = attribute(node.element, kAXEnabledAttribute) as? Bool, !enabled { return false }
        return true
    }

    private func awaitTextField(notification: AXUIElement, app: AXUIElement) -> AXUIElement? {
        let limit = min(Date().addingTimeInterval(1.5), job.deadline)
        var first = true
        repeat {
            let nodes = collect(roots: [notification], maxNodes: 400, maxDepth: 10, gatherParts: false)
            if let node = nodes.first(where: isEditable) { return node.element }
            if !first, let focused = elementAttribute(app, kAXFocusedUIElementAttribute), isInside(focused, container: notification) {
                let role = string(focused, kAXRoleAttribute) ?? ""
                let node = AXNode(element: focused, parent: -1, depth: 0, role: role, subrole: "", customActions: [], parts: [])
                if isEditable(node) { return focused }
            }
            first = false
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < limit
        return nil
    }

    private func isInside(_ element: AXUIElement, container: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        var hops = 0
        while let candidate = current, hops < 30 {
            if CFEqual(candidate, container) { return true }
            current = elementAttribute(candidate, kAXParentAttribute)
            hops += 1
        }
        return false
    }

    private func setText(_ field: AXUIElement) -> Bool {
        let text = request.text
        var applied = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString) == .success
        if !applied {
            applied = AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, text as CFString) == .success
        }
        guard applied else { return false }
        return string(field, kAXValueAttribute) == text
    }

    private func submit(field: AXUIElement, notification: AXUIElement) -> String {
        let nodes = collect(roots: [notification], maxNodes: 300, maxDepth: 8, gatherParts: false)
        for node in nodes where node.role == "AXButton" && isSendButton(node.element) {
            if AXUIElementPerformAction(node.element, kAXPressAction as CFString) == .success { return "button" }
        }
        if actionNames(field).contains(kAXConfirmAction as String),
           AXUIElementPerformAction(field, kAXConfirmAction as CFString) == .success {
            return "confirm"
        }
        postKey(36)
        return "return"
    }

    private func isSendButton(_ button: AXUIElement) -> Bool {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute] {
            guard let label = string(button, name) else { continue }
            let normalized = Self.normalize(label)
            if !normalized.isEmpty, Self.sendWords.contains(normalized) {
                return true
            }
        }
        return false
    }

    private func postKey(_ code: CGKeyCode) {
        guard ncPid != 0 else { return }
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
            event.postToPid(ncPid)
        }
    }

    private func awaitSent(_ field: AXUIElement, viaAction: Bool) -> Bool {
        let limit = min(Date().addingTimeInterval(1.5), job.deadline)
        repeat {
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(field, kAXRoleAttribute as CFString, &role)
            if error == .invalidUIElement { return viaAction }
            if error == .success, let value = string(field, kAXValueAttribute), value.isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < limit
        return false
    }

    private func findClockItem(_ controlCenter: AXUIElement) -> AXUIElement? {
        guard let bar = elementAttribute(controlCenter, "AXExtrasMenuBar") else { return nil }
        let items = elements(bar, kAXChildrenAttribute)
        return items.first(where: { string($0, kAXIdentifierAttribute) == "com.apple.menuextra.clock" })
    }

    private func controlCenterElement() -> AXUIElement? {
        guard let pid = Self.pid(of: Self.controlCenterBundleID) else { return nil }
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return element
    }

    private func openNotificationCenter(_ app: AXUIElement) -> Bool {
        guard let controlCenter = controlCenterElement(), let clock = findClockItem(controlCenter) else { return false }
        let before = elements(app, kAXWindowsAttribute).count
        guard AXUIElementPerformAction(clock, kAXPressAction as CFString) == .success else { return false }
        let limit = min(Date().addingTimeInterval(1.5), job.deadline)
        repeat {
            Thread.sleep(forTimeInterval: 0.1)
            if elements(app, kAXWindowsAttribute).count > before {
                openedNotificationCenter = true
                return true
            }
        } while Date() < limit
        return false
    }

    private func closeNotificationCenterIfOpened() {
        guard openedNotificationCenter else { return }
        openedNotificationCenter = false
        if let controlCenter = controlCenterElement(), let clock = findClockItem(controlCenter),
           AXUIElementPerformAction(clock, kAXPressAction as CFString) == .success {
            return
        }
        postKey(53)
    }
}
