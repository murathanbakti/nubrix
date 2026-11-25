import CoreGraphics
import Foundation
import os

protocol ScrollTapping: AnyObject {
    var isRunning: Bool { get }
    /// False when the tap could not be created (no Accessibility).
    func start(reverseHorizontal: Bool) -> Bool
    func update(reverseHorizontal: Bool)
    func stop()
}

/// An active event tap on its own thread, so the main thread never waits on scroll events.
final class ScrollWheelTap: ScrollTapping {
    private final class Context {
        private let horizontal = OSAllocatedUnfairLock(initialState: true)
        private let port = OSAllocatedUnfairLock<CFMachPort?>(initialState: nil)

        var reverseHorizontal: Bool {
            get { horizontal.withLock { $0 } }
            set { horizontal.withLock { $0 = newValue } }
        }

        var machPort: CFMachPort? {
            get { port.withLock { $0 } }
            set { port.withLock { $0 = newValue } }
        }
    }

    private struct Running {
        let runLoop: CFRunLoop
        let port: CFMachPort
    }

    private let context = Context()
    private let state = OSAllocatedUnfairLock<Running?>(initialState: nil)

    var isRunning: Bool { state.withLock { $0 != nil } }

    func start(reverseHorizontal: Bool) -> Bool {
        if isRunning {
            update(reverseHorizontal: reverseHorizontal)
            return true
        }
        context.reverseHorizontal = reverseHorizontal

        let ready = DispatchSemaphore(value: 0)
        // One lock covers "thread publishes its tap" and "caller gives up", so a late tap is never left running unowned.
        let handshake = OSAllocatedUnfairLock<(abandoned: Bool, running: Running?)>(initialState: (false, nil))
        let context = context
        let thread = Thread {
            let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let context = Unmanaged<Context>.fromOpaque(userInfo).takeUnretainedValue()
                    switch type {
                    case .tapDisabledByTimeout, .tapDisabledByUserInput:
                        if let port = context.machPort { CGEvent.tapEnable(tap: port, enable: true) }
                    case .scrollWheel:
                        ScrollReversal.apply(to: event, reverseHorizontal: context.reverseHorizontal)
                    default:
                        break
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(context).toOpaque()
            )
            guard let port, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
                ready.signal()
                return
            }
            let runLoop = CFRunLoopGetCurrent()!
            let published = handshake.withLock { state -> Bool in
                guard !state.abandoned else { return false }
                state.running = Running(runLoop: runLoop, port: port)
                return true
            }
            guard published else {
                CGEvent.tapEnable(tap: port, enable: false)
                CFMachPortInvalidate(port)
                return
            }
            context.machPort = port
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
        thread.name = "Nubrix.ScrollWheelTap"
        thread.qualityOfService = .userInteractive
        thread.start()

        _ = ready.wait(timeout: .now() + 2)
        let running = handshake.withLock { state -> Running? in
            if state.running == nil { state.abandoned = true }
            return state.running
        }
        guard let running else { return false }
        state.withLock { $0 = running }
        return true
    }

    func update(reverseHorizontal: Bool) {
        context.reverseHorizontal = reverseHorizontal
    }

    func stop() {
        guard let running = state.withLock({ current -> Running? in
            defer { current = nil }
            return current
        }) else { return }
        CGEvent.tapEnable(tap: running.port, enable: false)
        CFMachPortInvalidate(running.port)
        context.machPort = nil
        CFRunLoopStop(running.runLoop)
    }

    deinit { stop() }
}
