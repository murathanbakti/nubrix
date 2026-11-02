import Combine
import Defaults
import Foundation
import Network

final class AgentEventServer: @unchecked Sendable {
    static let shared = AgentEventServer()

    static let path = "/v1/claude/hook"
    static let maxConnections = 16
    static let maxPendingHeads = 12
    static let headTimeout: TimeInterval = 1
    static let bodyTimeout: TimeInterval = 5
    static let pingDeadline: TimeInterval = 0.5
    static let submitDeadline: TimeInterval = 1

    private final class ConnectionState {
        var pendingHead = true
        var timeout: DispatchWorkItem?
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var claimed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if claimed { return false }
            claimed = true
            return true
        }
    }

    private let queue = DispatchQueue(label: "dev.nubrix.agent-events")
    private var listener: NWListener?
    private var boundPort: UInt16?
    private var activeConnections = 0
    private var pendingHeads = 0
    private let tokenBytes: [UInt8]?
    private let token: String
    private var policyCancellable: AnyCancellable?

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

    static var shouldRun: Bool { Defaults[.claudeEnabled] || Defaults[.devEnabled] }

    func applyPolicy() {
        if policyCancellable == nil {
            policyCancellable = Defaults.publisher(keys: .claudeEnabled, .devEnabled, options: [])
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.applyPolicy() }
        }
        if Self.shouldRun { start() } else { stop() }
    }

    static var configDirectory: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/nubrix", isDirectory: true)
    }

    static var runDirectory: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingUTF8: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent(".config/nubrix-run", isDirectory: true)
    }

    static var endpointFile: URL { runDirectory.appendingPathComponent("agent-endpoint") }

    func start() {
        queue.async { [self] in
            guard listener == nil, Self.shouldRun else { return }
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
        let path = endpointFile.path
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 512)
        let count = read(fd, &buffer, buffer.count)
        close(fd)
        guard count > 0 else { return }
        let fields = String(decoding: buffer[0..<count], as: UTF8.self)
            .split(whereSeparator: { $0 == " " || $0 == "\n" })
        guard fields.count >= 3, let owner = pid_t(fields[2]) else { return }
        if owner == getpid() || (kill(owner, 0) != 0 && errno == ESRCH) {
            unlink(path)
        }
    }

    private static func prepareDirectory() throws {
        let fm = FileManager.default
        let directory = runDirectory
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
            let temp = Self.runDirectory.appendingPathComponent(".agent-endpoint.\(getpid()).tmp").path
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
        guard activeConnections < Self.maxConnections, pendingHeads < Self.maxPendingHeads else {
            connection.cancel()
            return
        }
        activeConnections += 1
        pendingHeads += 1
        let state = ConnectionState()
        connection.stateUpdateHandler = { [weak self] status in
            if case .cancelled = status, let self {
                self.activeConnections -= 1
                if state.pendingHead {
                    state.pendingHead = false
                    self.pendingHeads -= 1
                }
            }
        }
        connection.start(queue: queue)
        arm(state, connection, after: Self.headTimeout)
        receive(on: connection, buffer: Data(), head: nil, state: state)
    }

    private func arm(_ state: ConnectionState, _ connection: NWConnection, after seconds: TimeInterval) {
        state.timeout?.cancel()
        let timeout = DispatchWorkItem { connection.cancel() }
        state.timeout = timeout
        queue.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    private func receive(on connection: NWConnection, buffer: Data, head: HTTPHead?, state: ConnectionState) {
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
                    return self.receive(on: connection, buffer: buffer, head: nil, state: state)
                case .head(let parsed):
                    guard let port = self.boundPort else { return connection.cancel() }
                    switch AgentRoute.admit(parsed, token: self.token, port: port) {
                    case .reject:
                        return self.respond(connection, status: "404 Not Found")
                    case .refuse(let status):
                        return self.respond(connection, status: status)
                    case .accept(let maxBody):
                        guard parsed.contentLength <= maxBody else {
                            return self.respond(connection, status: "413 Payload Too Large")
                        }
                        head = parsed
                        if state.pendingHead {
                            state.pendingHead = false
                            self.pendingHeads -= 1
                        }
                        self.arm(state, connection, after: Self.bodyTimeout)
                    }
                }
            }

            guard let head else { return connection.cancel() }
            let end = head.bodyOffset + head.contentLength
            if buffer.count >= end {
                state.timeout?.cancel()
                let start = buffer.startIndex + head.bodyOffset
                let body = buffer.subdata(in: start..<(buffer.startIndex + end))
                let request = HTTPRequest(method: head.method, path: head.path, headers: head.headers, body: body)
                self.handle(request, on: connection)
            } else if closed {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer, head: head, state: state)
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
        if case .ping = outcome.action {
            answerPing(on: connection)
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
        case .permission, .ping:
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
        let gate = Gate()
        queue.asyncAfter(deadline: .now() + Self.submitDeadline) { [weak self] in
            guard gate.claim() else { return }
            let answer = AgentPermissionAnswer.none
            let proof = AgentProof.proof(key: key, nonce: nonce, decision: answer.decision, sessionID: sessionID)
            self?.respond(connection, status: "200 OK", body: answer.body(proof: proof))
        }
        Task { @MainActor in
            guard gate.claim() else { return }
            AgentPermissionStore.shared.submit(payload) { [weak self] answer in
                let proof = AgentProof.proof(key: key, nonce: nonce, decision: answer.decision, sessionID: sessionID)
                self?.respond(connection, status: "200 OK", body: answer.body(proof: proof))
            }
        }
    }

    private func answerPing(on connection: NWConnection) {
        let gate = Gate()
        queue.asyncAfter(deadline: .now() + Self.pingDeadline) {
            if gate.claim() { connection.cancel() }
        }
        Task { @MainActor in
            guard gate.claim() else { return }
            self.respond(connection, status: "204 No Content")
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
