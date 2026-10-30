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
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            if buffer.count > Self.maxRequestBytes { return self.respond(connection, status: "413 Payload Too Large") }

            switch HTTPRequest.parse(buffer) {
            case .complete(let request):
                self.handle(request, on: connection)
            case .invalid:
                self.respond(connection, status: "400 Bad Request")
            case .incomplete:
                if isComplete || error != nil { return connection.cancel() }
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        let outcome = AgentRoute.resolve(request, token: token)
        respond(connection, status: outcome.status)
        switch outcome.action {
        case .hook(let event):
            Task { @MainActor in AgentSessionStore.shared.apply(event) }
        case .notify(let notification):
            Task { @MainActor in DevNotificationStore.shared.post(notification) }
        case nil:
            break
        }
    }

    private func respond(_ connection: NWConnection, status: String) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
