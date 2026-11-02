import AppKit
import ApplicationServices
import CoreGraphics

enum NotificationReplyStatus: String {
    case sent
    case notFound
    case noAccess
    case unsupported
    case failed
    case unconfirmed

    func encoded() -> Data {
        (try? JSONSerialization.data(withJSONObject: ["status": rawValue])) ?? Data()
    }
}

final class NotificationReplier {
    private static let timeout: TimeInterval = 6
    private static let maxRequestBytes = 16 * 1024
    private let queue = DispatchQueue(label: "dev.nubrix.helper.notificationReply", qos: .userInitiated)

    func reply(_ data: Data, completion: @escaping (Data) -> Void) {
        let job = ReplyJob(deadline: Date().addingTimeInterval(Self.timeout), completion: completion)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.timeout) {
            job.finish(job.isSubmitted ? .unconfirmed : .failed)
        }
        guard data.count <= Self.maxRequestBytes, let request = ReplyRequest.parse(data) else {
            job.finish(.failed)
            return
        }
        queue.async {
            let status = ReplySession(job: job, request: request).run()
            job.finish(status)
        }
    }
}

private final class ReplyJob: @unchecked Sendable {
    let deadline: Date
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

    func markSubmitted() {
        lock.lock()
        submitted = true
        lock.unlock()
    }

    func finish(_ status: NotificationReplyStatus) {
        lock.lock()
        let already = finished
        finished = true
        lock.unlock()
        if !already { completion(status.encoded()) }
    }
}

private struct ReplyRequest {
    let appName: String
    let title: String
    let body: String
    let text: String

    private struct Raw: Decodable {
        var bundleID: String?
        var appName: String?
        var title: String?
        var body: String?
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
        return ReplyRequest(appName: String((raw.appName ?? "").prefix(500)), title: title, body: body, text: text)
    }
}

private struct AXNode {
    let element: AXUIElement
    let parent: Int
    let depth: Int
    let role: String
    let subrole: String
    var customActions: [String]
    var parts: [String]

    var isCandidate: Bool { subrole.hasPrefix("AXNotificationCenter") || !customActions.isEmpty }
}

private struct NotificationMatch {
    let element: AXUIElement
    let actions: [String]
    let subrole: String
    let text: String
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

    init(job: ReplyJob, request: ReplyRequest) {
        self.job = job
        self.request = request
    }

    func run() -> NotificationReplyStatus {
        guard AXIsProcessTrusted() else { return .noAccess }
        guard let pid = Self.pid(of: Self.ncBundleID) else { return .notFound }
        ncPid = pid
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        defer { closeNotificationCenterIfOpened() }

        switch locate(app) {
        case .found(let match):
            return perform(match, app: app)
        case .blocked:
            return .notFound
        case .missing:
            break
        }

        guard !job.isExpired, openNotificationCenter(app) else { return .notFound }
        if case .found(let match) = locate(app) {
            return perform(match, app: app)
        }
        return .notFound
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
            case 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0xFEFF, 0x00AD, 0xFE00...0xFE0F:
                continue
            default:
                if scalar.properties.generalCategory == .control, !scalar.properties.isWhitespace { continue }
                scalars.append(scalar)
            }
        }
        return String(scalars)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private func makeNode(_ element: AXUIElement, parent: Int, depth: Int, gatherParts: Bool) -> AXNode {
        let role = string(element, kAXRoleAttribute) ?? ""
        let subrole = string(element, kAXSubroleAttribute) ?? ""
        var parts: [String] = []
        if gatherParts, role == "AXStaticText" {
            for name in [kAXValueAttribute, kAXDescriptionAttribute, kAXTitleAttribute] {
                if let text = string(element, name), !text.isEmpty { parts.append(text) }
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

    private func locate(_ app: AXUIElement) -> LocateResult {
        let windows = elements(app, kAXWindowsAttribute)
        guard !windows.isEmpty else { return .missing }
        let nodes = collect(roots: windows, maxNodes: Self.maxNodes, maxDepth: Self.maxDepth, gatherParts: true)
        guard !job.isExpired else { return .missing }

        var texts = [[String]](repeating: [], count: nodes.count)
        for (index, node) in nodes.enumerated() where node.isCandidate {
            for name in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute] {
                if let text = string(node.element, name), !text.isEmpty { texts[index].append(text) }
            }
        }
        for node in nodes where !node.parts.isEmpty {
            var ancestor = node.parent
            var distance = 1
            while ancestor >= 0, distance <= 6 {
                if nodes[ancestor].isCandidate { texts[ancestor].append(contentsOf: node.parts) }
                ancestor = nodes[ancestor].parent
                distance += 1
            }
        }

        let title = Self.normalize(request.title)
        let body = Self.normalize(request.body)
        let bodyKey = String(body.prefix(min(40, body.count)))
        let appName = Self.normalize(request.appName)

        var matches: [Int] = []
        var combined: [Int: String] = [:]
        for (index, node) in nodes.enumerated() where node.isCandidate {
            let text = Self.normalize(texts[index].joined(separator: " "))
            guard !text.isEmpty else { continue }
            if !title.isEmpty, !text.contains(title) { continue }
            if !bodyKey.isEmpty, !text.contains(bodyKey) { continue }
            matches.append(index)
            combined[index] = text
        }
        guard !matches.isEmpty else { return .missing }

        var hasMatchingDescendant = Set<Int>()
        for index in matches {
            var ancestor = nodes[index].parent
            while ancestor >= 0 {
                hasMatchingDescendant.insert(ancestor)
                ancestor = nodes[ancestor].parent
            }
        }
        var innermost = matches.filter { !hasMatchingDescendant.contains($0) }
        let individual = innermost.filter { !nodes[$0].subrole.contains("Stack") }
        guard !individual.isEmpty else { return .blocked }
        innermost = individual

        if !appName.isEmpty {
            let withApp = innermost.filter { combined[$0]?.contains(appName) == true }
            if !withApp.isEmpty { innermost = withApp }
        }

        guard let first = innermost.first else { return .missing }
        let firstText = combined[first] ?? ""
        for index in innermost where combined[index] != firstText { return .blocked }

        let node = nodes[first]
        return .found(NotificationMatch(element: node.element, actions: node.customActions,
                                        subrole: node.subrole, text: firstText))
    }

    private func isReplyAction(_ action: String) -> Bool {
        let name = Self.normalize(Self.displayName(of: action))
        guard !name.isEmpty else { return false }
        return Self.replyWords.contains { name == $0 || name.hasPrefix($0) }
    }

    private func perform(_ match: NotificationMatch, app: AXUIElement) -> NotificationReplyStatus {
        guard let action = match.actions.first(where: isReplyAction) else { return .unsupported }
        guard !job.isExpired else { return .failed }
        guard AXUIElementPerformAction(match.element, action as CFString) == .success else { return .failed }

        guard let field = awaitTextField(notification: match.element, app: app) else { return .failed }
        guard !job.isExpired, setText(field) else {
            _ = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFString)
            return .failed
        }
        guard !job.isExpired else {
            _ = AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, "" as CFString)
            return .failed
        }

        job.markSubmitted()
        submit(field: field, notification: match.element)
        return awaitSent(field) ? .sent : .unconfirmed
    }

    private func isEditable(_ node: AXNode) -> Bool {
        guard Self.editableRoles.contains(node.role) else { return false }
        if let enabled = attribute(node.element, kAXEnabledAttribute) as? Bool, !enabled { return false }
        return true
    }

    private func awaitTextField(notification: AXUIElement, app: AXUIElement) -> AXUIElement? {
        let limit = min(Date().addingTimeInterval(1.5), job.deadline)
        repeat {
            let nodes = collect(roots: [notification], maxNodes: 400, maxDepth: 10, gatherParts: false)
            if let node = nodes.first(where: isEditable) { return node.element }
            if let focused = elementAttribute(app, kAXFocusedUIElementAttribute) {
                let role = string(focused, kAXRoleAttribute) ?? ""
                let node = AXNode(element: focused, parent: -1, depth: 0, role: role, subrole: "", customActions: [], parts: [])
                if isEditable(node) { return focused }
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < limit
        return nil
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

    private func submit(field: AXUIElement, notification: AXUIElement) {
        var roots = [notification]
        var ancestor = elementAttribute(field, kAXParentAttribute)
        var hops = 0
        while let current = ancestor, hops < 3 {
            roots.append(current)
            ancestor = elementAttribute(current, kAXParentAttribute)
            hops += 1
        }
        for root in roots {
            let nodes = collect(roots: [root], maxNodes: 300, maxDepth: 8, gatherParts: false)
            for node in nodes where node.role == "AXButton" && isSendButton(node.element) {
                if AXUIElementPerformAction(node.element, kAXPressAction as CFString) == .success { return }
            }
        }
        if actionNames(field).contains(kAXConfirmAction as String),
           AXUIElementPerformAction(field, kAXConfirmAction as CFString) == .success {
            return
        }
        postKey(36)
    }

    private func isSendButton(_ button: AXUIElement) -> Bool {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute] {
            guard let label = string(button, name) else { continue }
            let normalized = Self.normalize(label)
            if !normalized.isEmpty, Self.sendWords.contains(where: { normalized == $0 || normalized.hasPrefix($0) }) {
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

    private func awaitSent(_ field: AXUIElement) -> Bool {
        let limit = min(Date().addingTimeInterval(1.5), job.deadline)
        repeat {
            var role: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(field, kAXRoleAttribute as CFString, &role)
            if error == .invalidUIElement { return true }
            if error == .success, let value = string(field, kAXValueAttribute), value.isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < limit
        return false
    }

    private func findClockItem(_ controlCenter: AXUIElement) -> AXUIElement? {
        guard let bar = elementAttribute(controlCenter, "AXExtrasMenuBar") else { return nil }
        let items = elements(bar, kAXChildrenAttribute)
        if let byID = items.first(where: { string($0, kAXIdentifierAttribute) == "com.apple.menuextra.clock" }) {
            return byID
        }
        guard let pattern = try? NSRegularExpression(pattern: "\\d{1,2}[:.]\\d{2}") else { return nil }
        return items.first { item in
            guard (string(item, kAXRoleAttribute) ?? "") == "AXMenuBarItem" else { return false }
            return [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute].contains { name in
                guard let text = string(item, name) else { return false }
                return pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
            }
        }
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
        openedNotificationCenter = true
        let limit = min(Date().addingTimeInterval(1.5), job.deadline)
        repeat {
            Thread.sleep(forTimeInterval: 0.1)
            if elements(app, kAXWindowsAttribute).count > before {
                Thread.sleep(forTimeInterval: 0.25)
                return true
            }
        } while Date() < limit
        return true
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
