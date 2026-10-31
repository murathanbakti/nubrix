import Foundation
import Network

final class AgentEventServer: @unchecked Sendable {
    static let shared = AgentEventServer()

    static let path = "/v1/claude/hook"
    static let maxConnections = 16

    private let queue = DispatchQueue(label: "dev.nubrix.agent-events")
    private var listener: NWListener?
    private var boundPort: UInt16?
    private var activeConnections = 0
    private let tokenBytes: [UInt8]?
    private let token: String

    private init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
            tokenBytes = bytes
            token = AgentProof.hex(bytes)
        } else {
            tokenBytes = nil
            token = ""
        }
    }

    static var configDirectory: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/nubrix", isDirectory: true)
    }

    static var endpointFile: URL { configDirectory.appendingPathComponent("agent-endpoint") }

    func start() {
        queue.async { [self] in
            guard listener == nil else { return }
            guard tokenBytes != nil else {
                NSLog("Nubrix agent server not started: no random token")
                return
            }
            Self.removeEndpoint()
            do {
                let parameters = NWParameters.tcp
                parameters.acceptLocalOnly = true
                parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                let listener = try NWListener(using: parameters)
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    switch state {
                    case .ready:
                        if let port = listener?.port?.rawValue {
                            self?.boundPort = port
                            Task { @MainActor in AgentSessionStore.shared.serverPort = port }
                            self?.publishEndpoint(port: port)
                        }
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
            Self.removeEndpoint()
            listener?.cancel()
            listener = nil
            boundPort = nil
        }
    }

    private func restart() {
        Self.removeEndpoint()
        listener?.cancel()
        listener = nil
        boundPort = nil
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }

    private static func removeEndpoint() {
        Task { @MainActor in AgentSessionStore.shared.serverPort = nil }
        unlink(endpointFile.path)
    }

    private static func prepareDirectory() throws {
        let fm = FileManager.default
        let directory = configDirectory
        var info = stat()
        if lstat(directory.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            guard info.st_uid == getuid() else { throw CocoaError(.fileWriteNoPermission) }
        } else {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
        }
        guard chmod(directory.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
    }

    private func publishEndpoint(port: UInt16) {
        do {
            try Self.prepareDirectory()
            let final = Self.endpointFile.path
            let temp = Self.configDirectory.appendingPathComponent(".agent-endpoint.\(getpid()).tmp").path
            unlink(temp)
            let fd = open(temp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let bytes = Array("\(port) \(token) \(getpid())\n".utf8)
            let written = bytes.withUnsafeBufferPointer { write(fd, $0.baseAddress, $0.count) }
            let modeSet = fchmod(fd, 0o600) == 0
            close(fd)
            guard written == bytes.count, modeSet, rename(temp, final) == 0 else {
                unlink(temp)
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            NSLog("Nubrix agent server could not write endpoint: \(error)")
        }
    }

    private func accept(_ connection: NWConnection) {
        guard activeConnections < Self.maxConnections else {
            connection.cancel()
            return
        }
        activeConnections += 1
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state { self?.activeConnections -= 1 }
        }
        connection.start(queue: queue)
        let timeout = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + 5, execute: timeout)
        receive(on: connection, buffer: Data(), head: nil, timeout: timeout)
    }

    private func receive(on connection: NWConnection, buffer: Data, head: HTTPHead?, timeout: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            var head = head
            if let chunk { buffer.append(chunk) }
            let closed = isComplete || error != nil

            if head == nil {
                switch HTTPRequest.parseHead(buffer) {
                case .invalid:
                    return connection.cancel()
                case .incomplete:
                    if closed { return connection.cancel() }
                    return self.receive(on: connection, buffer: buffer, head: nil, timeout: timeout)
                case .head(let parsed):
                    guard let port = self.boundPort else { return connection.cancel() }
                    switch AgentRoute.admit(parsed, token: self.token, port: port) {
                    case .reject:
                        return self.respond(connection, status: "404 Not Found")
                    case .accept(let maxBody):
                        guard parsed.contentLength <= maxBody else {
                            return self.respond(connection, status: "413 Payload Too Large")
                        }
                        head = parsed
                    }
                }
            }

            guard let head else { return connection.cancel() }
            let end = head.bodyOffset + head.contentLength
            if buffer.count >= end {
                timeout.cancel()
                let start = buffer.startIndex + head.bodyOffset
                let body = buffer.subdata(in: start..<(buffer.startIndex + end))
                let request = HTTPRequest(method: head.method, path: head.path, headers: head.headers, body: body)
                self.handle(request, on: connection)
            } else if closed {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer, head: head, timeout: timeout)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        let outcome = AgentRoute.resolve(request, token: token)
        if case .permission(let payload, let nonce) = outcome.action {
            Task { @MainActor in AgentSessionStore.shared.notePermissionRequest() }
            holdPermission(payload, nonce: nonce, on: connection)
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

    private func holdPermission(_ payload: AgentPermissionPayload, nonce: String, on connection: NWConnection) {
        let id = payload.id
        let sessionID = payload.sessionID
        let key = tokenBytes ?? []
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
            if isComplete || error != nil {
                Task { @MainActor in AgentPermissionStore.shared.withdraw(id) }
            }
        }
        Task { @MainActor in
            AgentPermissionStore.shared.submit(payload) { [weak self] answer in
                let proof = AgentProof.proof(key: key, nonce: nonce, decision: answer.decision, sessionID: sessionID)
                self?.respond(connection, status: "200 OK", body: answer.body(proof: proof))
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
