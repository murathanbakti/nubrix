import Foundation

enum AgentRoute {
    static let hookPath = "/v1/claude/hook"
    static let statusPath = "/v1/claude/status"
    static let permissionPath = "/v1/claude/permission"
    static let maxPermissionBytes = 64 * 1024
    static let maxHookBytes = 512 * 1024
    static let maxStatusBytes = 128 * 1024
    static let maxNotifyBytes = 16 * 1024
    static let singletonHeaders = ["authorization", "content-length", "host", "x-nubrix-nonce", "x-nubrix-wait"]
    static let notifyPath = "/v1/notify"
    static let pingPath = "/v1/ping"

    enum Action {
        case hook(AgentHookEvent)
        case status(AgentStatusUpdate)
        case permission(AgentPermissionPayload, nonce: String)
        case notify(DevNotifyRequest)
    }

    struct Outcome {
        let status: String
        let action: Action?
    }

    enum Admission: Equatable {
        case reject
        case accept(maxBody: Int)
    }

    private static func normalizedPath(_ raw: String) -> String {
        raw.split(separator: "?", maxSplits: 1).first.map(String.init) ?? raw
    }

    private static func maxBody(method: String, path: String) -> Int? {
        switch (method, path) {
        case ("POST", hookPath): return maxHookBytes
        case ("POST", statusPath): return maxStatusBytes
        case ("POST", permissionPath): return maxPermissionBytes
        case ("POST", notifyPath): return maxNotifyBytes
        case ("GET", pingPath): return 0
        default: return nil
        }
    }

    static func admit(_ head: HTTPHead, token: String, port: UInt16) -> Admission {
        guard let limit = maxBody(method: head.method, path: normalizedPath(head.path)) else { return .reject }
        guard head.headers["origin"] == nil else { return .reject }
        guard head.duplicates.isDisjoint(with: singletonHeaders) else { return .reject }
        let host = (head.headers["host"] ?? "").lowercased()
        guard host == "127.0.0.1:\(port)" || host == "localhost:\(port)" else { return .reject }
        guard constantTimeEquals(head.headers["authorization"] ?? "", "Bearer \(token)") else { return .reject }
        return .accept(maxBody: limit)
    }

    static func resolve(_ request: HTTPRequest, token: String) -> Outcome {
        let path = normalizedPath(request.path)
        guard maxBody(method: request.method, path: path) != nil,
              constantTimeEquals(request.headers["authorization"] ?? "", "Bearer \(token)")
        else { return Outcome(status: "404 Not Found", action: nil) }
        switch path {
        case hookPath:
            guard var event = AgentHookEvent(json: request.body) else {
                return Outcome(status: "422 Unprocessable Entity", action: nil)
            }
            event.source = AgentSourceInfo(headers: request.headers)
            event.branch = branch(request)
            return Outcome(status: "204 No Content", action: .hook(event))
        case statusPath:
            guard var update = AgentStatusUpdate(json: request.body) else {
                return Outcome(status: "422 Unprocessable Entity", action: nil)
            }
            update.source = AgentSourceInfo(headers: request.headers)
            update.branch = branch(request)
            return Outcome(status: "204 No Content", action: .status(update))
        case permissionPath:
            guard request.body.count <= maxPermissionBytes else {
                return Outcome(status: "413 Payload Too Large", action: nil)
            }
            let nonce = request.headers["x-nubrix-nonce"] ?? ""
            guard AgentProof.isValidNonce(nonce) else {
                return Outcome(status: "400 Bad Request", action: nil)
            }
            guard let payload = AgentPermissionPayload(
                json: request.body,
                waitHeader: request.headers["x-nubrix-wait"],
                source: AgentSourceInfo(headers: request.headers)
            ) else {
                return Outcome(status: "422 Unprocessable Entity", action: nil)
            }
            return Outcome(status: "200 OK", action: .permission(payload, nonce: nonce))
        case notifyPath:
            switch DevNotifyRequest.parse(request.body) {
            case .success(let notification):
                return Outcome(status: "204 No Content", action: .notify(notification))
            case .failure(.malformed):
                return Outcome(status: "400 Bad Request", action: nil)
            case .failure(.invalid):
                return Outcome(status: "422 Unprocessable Entity", action: nil)
            }
        default:
            return Outcome(status: "204 No Content", action: nil)
        }
    }

    private static func branch(_ request: HTTPRequest) -> String? {
        let value = AgentText.sanitized(request.headers["x-nubrix-branch"], limit: 100)
        return value.isEmpty ? nil : value
    }

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
