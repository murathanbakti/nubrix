import Defaults
import Foundation
import Network

struct DevServer: Identifiable, Equatable {
    let port: Int
    let label: String
    let isDatabase: Bool
    var id: Int { port }
    var address: String { "localhost:\(port)" }
}

@MainActor
final class DevPortMonitor: ObservableObject {
    static let shared = DevPortMonitor()

    @Published private(set) var servers: [DevServer] = []
    @Published private(set) var lastScan: Date?

    private var observers = Set<String>()
    private var loop: Task<Void, Never>?
    private var scanning = false

    private init() {}

    func setActive(_ owner: String, _ active: Bool) {
        if active { observers.insert(owner) } else { observers.remove(owner) }
        if observers.isEmpty {
            loop?.cancel()
            loop = nil
        } else if loop == nil {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.scan()
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }

    func refresh() {
        Task { await scan() }
    }

    private func scan() async {
        guard !scanning, Defaults[.devEnabled] else { return }
        scanning = true
        defer { scanning = false }
        let ports = Defaults[.devPorts]
        let open = await Self.probe(ports: ports)
        guard !Task.isCancelled else { return }
        let next = ports.filter(open.contains).map { port -> DevServer in
            let info = DevPortCatalog.info(for: port)
            return DevServer(port: port, label: info.label, isDatabase: info.isDatabase)
        }
        if next != servers { servers = next }
        lastScan = Date()
    }

    nonisolated private static func probe(ports: [Int]) async -> Set<Int> {
        await withTaskGroup(of: Int?.self) { group in
            for port in ports {
                group.addTask { await isOpen(port: port) ? port : nil }
            }
            var result = Set<Int>()
            for await port in group { if let port { result.insert(port) } }
            return result
        }
    }

    nonisolated private static func isOpen(port: Int) async -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return false }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "dev.nubrix.port-probe")
            let connection = NWConnection(host: .ipv4(.loopback), port: nwPort, using: .tcp)
            let gate = ProbeGate(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.finish(true, connection)
                case .failed, .cancelled:
                    gate.finish(false, connection)
                case .waiting:
                    gate.finish(false, connection)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 0.3) { gate.finish(false, connection) }
        }
    }
}

private final class ProbeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Bool, _ connection: NWConnection) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        connection.cancel()
        pending.resume(returning: value)
    }
}
