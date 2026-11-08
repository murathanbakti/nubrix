import XCTest
@testable import Nubrix

final class LatestWinsWriterTests: XCTestCase {
    func testOnlyNewestPendingValueIsKept() {
        let writer = LatestWinsWriter()
        XCTAssertTrue(writer.enqueue(0.1))
        // While the first write is in flight, newer values replace each other.
        XCTAssertFalse(writer.enqueue(0.2))
        XCTAssertFalse(writer.enqueue(0.3))
        XCTAssertEqual(writer.next(), 0.3)
        XCTAssertNil(writer.next())
        // Loop stopped, so the next value starts a new one.
        XCTAssertTrue(writer.enqueue(0.5))
    }

    func testSubmitSendsInOrderAndEndsOnNewest() async {
        let writer = LatestWinsWriter()
        let sent = Locked<[Float]>([])
        let finished = expectation(description: "done")
        let gate = AsyncGate()
        for value in [Float(0.1), 0.2, 0.3, 0.4] {
            writer.submit(value, send: { v in
                await gate.wait()
                sent.mutate { $0.append(v) }
                return true
            }, done: { v, _ in if v == 0.4 { finished.fulfill() } })
        }
        await gate.open()
        await fulfillment(of: [finished], timeout: 2)
        let values = sent.value
        XCTAssertEqual(values.last, 0.4)
        XCTAssertEqual(values, values.sorted())
        XCTAssertLessThanOrEqual(values.count, 2)
    }
}

private final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ body: (inout T) -> Void) { lock.lock(); body(&stored); lock.unlock() }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
