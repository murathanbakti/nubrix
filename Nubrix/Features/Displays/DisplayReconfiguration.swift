import AppKit
import CoreGraphics

// MARK: - Settling rules (pure)

/// Tracks a display reconfiguration (a display added or removed, mirroring turned on or off, AirPlay
/// starting) so Nubrix leaves its windows alone until the displays have settled.
///
/// macOS reports every step of a reconfiguration, often several times in a row. Reacting to each one
/// (closing and recreating windows, adding them to a private window space) while the window server is
/// still rebuilding the displays can get in its way.
struct DisplayReconfigurationGate: Equatable {
    /// How long the displays must stay unchanged before Nubrix touches its windows again.
    static let settle: TimeInterval = 1
    /// Short pause that merges bursts of screen-parameter notifications into one refresh.
    static let debounce: TimeInterval = 0.3
    /// A "begin" with no later callback counts as finished after this long, so a lost callback can
    /// never keep the notch hidden.
    static let maxInProgress: TimeInterval = 5

    private(set) var inProgress = false
    private(set) var lastEvent: Date?

    /// Records one callback from `CGDisplayRegisterReconfigurationCallback`. Returns true when it
    /// starts a new reconfiguration (the gate was quiet before it).
    @discardableResult
    mutating func record(flags: CGDisplayChangeSummaryFlags, at now: Date) -> Bool {
        let wasQuiet = isQuiet(at: now)
        lastEvent = now
        inProgress = flags.contains(.beginConfigurationFlag)
        return wasQuiet
    }

    /// True when no reconfiguration is running and the last one finished at least `settle` ago.
    func isQuiet(at now: Date) -> Bool {
        guard let lastEvent else { return true }
        let elapsed = now.timeIntervalSince(lastEvent)
        return (!inProgress || elapsed >= Self.maxInProgress) && elapsed >= Self.settle
    }

    /// Seconds until the displays count as settled (0 when they already do).
    func timeUntilQuiet(at now: Date) -> TimeInterval {
        guard let lastEvent else { return 0 }
        let elapsed = now.timeIntervalSince(lastEvent)
        if inProgress { return min(Self.settle, max(0, Self.maxInProgress - elapsed)) }
        return max(0, Self.settle - elapsed)
    }

    /// How long to wait before refreshing windows after a screen-parameter change: the debounce, or
    /// longer while the displays are still settling.
    func delayBeforeRefresh(at now: Date) -> TimeInterval {
        max(Self.debounce, timeUntilQuiet(at: now))
    }
}

/// Which screens get a notch window.
enum NotchScreenFilter {
    /// A display that only mirrors another one (AirPlay, cable mirroring) shows the same picture as its
    /// source, so it gets no window of its own: the source's window already appears on it.
    static func hostsNotch(mirrorsDisplay source: CGDirectDisplayID) -> Bool {
        source == kCGNullDirectDisplay
    }

    /// UUIDs from `screens` that should have a window, in order.
    static func eligible(_ screens: [(uuid: String, mirrorsDisplay: CGDirectDisplayID)]) -> [String] {
        screens.filter { hostsNotch(mirrorsDisplay: $0.mirrorsDisplay) }.map(\.uuid)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// False for a display that only mirrors another one.
    var hostsNotch: Bool {
        guard let displayID else { return true }
        return NotchScreenFilter.hostsNotch(mirrorsDisplay: CGDisplayMirrorsDisplay(displayID))
    }
}

// MARK: - Watcher

/// Listens to display reconfigurations and says when one starts and when the displays have settled.
@MainActor
final class DisplayReconfigurationWatcher {
    static let shared = DisplayReconfigurationWatcher()

    /// A reconfiguration started (not called again until the displays have settled).
    var onBegin: (() -> Void)?
    /// The displays have been unchanged for `DisplayReconfigurationGate.settle` seconds.
    var onSettled: (() -> Void)?

    private(set) var gate = DisplayReconfigurationGate()
    private var settleTask: Task<Void, Never>?
    private var started = false
    private var episodeOpen = false

    var isQuiet: Bool { gate.isQuiet(at: Date()) }

    func start() {
        guard !started else { return }
        started = true
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, nil)
    }

    func stop() {
        guard started else { return }
        started = false
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, nil)
        settleTask?.cancel()
        settleTask = nil
    }

    fileprivate func handle(flags: CGDisplayChangeSummaryFlags) {
        let starts = gate.record(flags: flags, at: Date())
        if starts || !episodeOpen {
            episodeOpen = true
            onBegin?()
        }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let wait = self.gate.timeUntilQuiet(at: Date())
                try? await Task.sleep(for: .seconds(max(wait, 0.05)))
                if Task.isCancelled { return }
                if self.gate.isQuiet(at: Date()) {
                    self.episodeOpen = false
                    self.onSettled?()
                    return
                }
            }
        }
    }
}

/// Runs on the main thread, called by macOS. Does nothing but note the event.
private func displayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ userInfo: UnsafeMutableRawPointer?) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated { DisplayReconfigurationWatcher.shared.handle(flags: flags) }
    }
}
