import Foundation

enum AgentRoute {
    static let hookPath = "/v1/claude/hook"
    static let notifyPath = "/v1/notify"
    static let pingPath = "/v1/ping"

    enum Action {
        case hook(AgentHookEvent)
        case notify(DevNotifyRequest)
    }

    struct Outcome {
        let status: String
        let action: Action?
    }

    static func resolve(_ request: HTTPRequest, token: String) -> Outcome {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        let known = (request.method == "POST" && (path == hookPath || path == notifyPath))
            || (request.method == "GET" && path == pingPath)
        guard known else { return Outcome(status: "404 Not Found", action: nil) }
        guard constantTimeEquals(request.headers["authorization"] ?? "", "Bearer \(token)") else {
            return Outcome(status: "401 Unauthorized", action: nil)
        }
        switch path {
        case hookPath:
            guard let event = AgentHookEvent(json: request.body) else {
                return Outcome(status: "422 Unprocessable Entity", action: nil)
            }
            return Outcome(status: "204 No Content", action: .hook(event))
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

    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}
