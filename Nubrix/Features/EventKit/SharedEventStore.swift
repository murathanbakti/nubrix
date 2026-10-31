@preconcurrency import EventKit
import Combine
import Foundation

final class EventStoreChangeHub: @unchecked Sendable {
    static let defaultDebounce: TimeInterval = 0.3

    private let subject = PassthroughSubject<Void, Never>()
    private var upstream: AnyCancellable?
    private let lock = NSLock()
    private var count = 0

    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }

    var emissionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    init(
        center: NotificationCenter = .default,
        name: Notification.Name = .EKEventStoreChanged,
        object: AnyObject? = nil,
        debounce: TimeInterval = EventStoreChangeHub.defaultDebounce,
        queue: DispatchQueue = .main
    ) {
        upstream = center.publisher(for: name, object: object)
            .map { _ in () }
            .debounce(for: .seconds(debounce), scheduler: queue)
            .sink { [weak self] in
                guard let self else { return }
                self.lock.lock()
                self.count += 1
                self.lock.unlock()
                self.subject.send()
            }
    }
}

struct EventKitBox<Value>: @unchecked Sendable {
    let value: Value
}

final class SharedEventStore: @unchecked Sendable {
    static let shared = SharedEventStore()

    let store = EKEventStore()
    let queue = DispatchQueue(label: "dev.nubrix.eventkit", qos: .userInitiated)
    let hub: EventStoreChangeHub

    var changes: AnyPublisher<Void, Never> { hub.changes }

    private init() {
        hub = EventStoreChangeHub(object: store)
    }

    func perform<T>(_ work: @escaping @Sendable (EKEventStore) -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work(self.store)) }
        }
    }

    func performSync<T>(_ work: (EKEventStore) throws -> T) rethrows -> T {
        try queue.sync { try work(store) }
    }
}
