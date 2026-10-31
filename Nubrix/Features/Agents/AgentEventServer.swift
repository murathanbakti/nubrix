import Foundation
import Network

final class AgentEventServer: @unchecked Sendable {
    static let shared = AgentEventServer()

    static let path = "/v1/claude/hook"
    private static let maxRequestBytes = 512 * 1024

    private let queue = DispatchQueue(label: "dev.nubrix.agent-events")
    private var listener: NWListener?
    private let token: String

    private init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        token = bytes.map { String(format: "%02x", $0) }.joined()
    }

    static var configDirectory: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/nubrix", isDirectory: true)
    }

    static var endpointFile: URL { configDirectory.appendingPathComponent("agent-endpoint") }

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            do {
                let parameters = NWParameters.tcp
                parameters.acceptLocalOnly = true
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                let listener = try NWListener(using: parameters)
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    switch state {
                    case .ready:
                        if let port = listener?.port?.rawValue { self?.publishEndpoint(port: port) }
                    case .failed(let error):
                        NSLog("Nubrix agent server failed: \(error)")
                        self?.restart()
                    default:
                        break
                    }
                }
                self.listener = listener
                listener.start(queue: queue)
            } catch {
                NSLog("Nubrix agent server could not start: \(error)")
            }
        }
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            try? FileManager.default.removeItem(at: Self.endpointFile)
        }
    }

    private func restart() {
        listener?.cancel()
        listener = nil
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }

    private func publishEndpoint(port: UInt16) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.configDirectory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let data = Data("\(port) \(token)\n".utf8)
            try data.write(to: Self.endpointFile, options: [.atomic])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.endpointFile.path)
        } catch {
            NSLog("Nubrix agent server could not write endpoint: \(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        let timeout = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + 5, execute: timeout)
        receive(on: connection, buffer: Data(), timeout: timeout)
    }

    private func receive(on connection: NWConnection, buffer: Data, timeout: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if buffer.count > Self.maxRequestBytes { return self.respond(connection, status: "413 Payload Too Large") }

            switch HTTPRequest.parse(buffer) {
            case .complete(let request):
                timeout.cancel()
                self.handle(request, on: connection)
            case .invalid:
                self.respond(connection, status: "400 Bad Request")
            case .incomplete:
                if isComplete || error != nil { return connection.cancel() }
                self.receive(on: connection, buffer: buffer, timeout: timeout)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        let outcome = AgentRoute.resolve(request, token: token)
        if case .permission(let payload) = outcome.action {
            holdPermission(payload, on: connection)
            return
        }
        respond(connection, status: outcome.status)
        switch outcome.action {
        case .hook(let event):
            Task { @MainActor in
                AgentSessionStore.shared.apply(event)
                AgentPermissionStore.shared.observe(event)
            }
        case .status(let update):
            Task { @MainActor in AgentSessionStore.shared.apply(update) }
        case .permission:
            break
        case .notify(let notification):
            Task { @MainActor in DevNotificationStore.shared.post(notification) }
        case nil:
            break
        }
    }

    private func holdPermission(_ payload: AgentPermissionPayload, on connection: NWConnection) {
        let id = payload.id
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            if isComplete || error != nil {
                Task { @MainActor in AgentPermissionStore.shared.withdraw(id) }
            }
        }
        Task { @MainActor in
            AgentPermissionStore.shared.submit(payload) { [weak self] answer in
                self?.respond(connection, status: "200 OK", body: answer.body)
            }
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String? = nil) {
        let payload = Data((body ?? "").utf8)
        var head = "HTTP/1.1 \(status)\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n"
        if body != nil { head += "Content-Type: application/json\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in connection.cancel() })
    }
}
