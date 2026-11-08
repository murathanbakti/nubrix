import AppKit
import Combine
import CoreGraphics
import Defaults
import Foundation

// MARK: - State (pure)

/// What Nubrix knows about the screen being seen by someone else.
struct ScreenShareState: Equatable {
    /// Another app is capturing or sharing the screen (screen sharing, recording, a video call).
    var watched = false
    /// Name of the display that mirrors this screen (AirPlay or cable), if any.
    var mirroringTo: String?

    var isShared: Bool { watched || mirroringTo != nil }

    /// Second line of the Controls banner.
    var detail: String {
        if let mirroringTo { return "Mirroring to \(mirroringTo)" }
        return "Another app can see your screen"
    }
}

enum ScreenShareAlerts {
    static func alert(hidden: Bool, state: ScreenShareState) -> EverydayAlert {
        EverydayAlert(
            symbol: "rectangle.on.rectangle", tint: .orange, title: "Screen is shared",
            detail: state.mirroringTo.map { "Mirroring to \($0)" },
            headerTitle: "Screen is shared", meta: hidden ? "Notch hidden" : "Notch visible", opensControls: true)
    }
}

/// Alerts once each time the screen goes from not shared to shared. The first read only records the
/// state, so launching Nubrix during a call is silent.
struct ScreenShareTracker {
    private var seeded = false
    private var shared = false

    mutating func update(_ state: ScreenShareState, notchHidden: Bool) -> EverydayAlert? {
        defer { seeded = true; shared = state.isShared }
        guard seeded, state.isShared, !shared else { return nil }
        return ScreenShareAlerts.alert(hidden: notchHidden, state: state)
    }
}

// MARK: - Quick toggle

enum ControlsMirroring {
    static let settingsURL = "x-apple.systempreferences:com.apple.Displays-Settings.extension"

    static func toggle(mirroringTo: String?) -> ControlsToggleState {
        if let mirroringTo {
            return ControlsToggleState(
                symbol: "rectangle.on.rectangle", label: "Mirroring", fill: .accent,
                help: "Mirroring to \(mirroringTo). Open Displays settings to stop")
        }
        return ControlsToggleState(
            symbol: "rectangle.on.rectangle", label: "Mirroring", fill: .neutral,
            help: "Open Displays settings to mirror this screen to an AirPlay display or TV")
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: settingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Reading

enum ScreenShareReader {
    private typealias WatcherPresent = @convention(c) () -> Bool

    /// SkyLight's own "is something watching the screen" check. Returns false when the call is missing.
    /// It only answers yes or no; nothing is captured and no permission is involved.
    static let isWatchedProbe: (() -> Bool)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW) else { return nil }
        for name in ["SLSIsScreenWatcherPresent", "CGSIsScreenWatcherPresent"] {
            if let symbol = dlsym(handle, name) {
                let function = unsafeBitCast(symbol, to: WatcherPresent.self)
                return { function() }
            }
        }
        return nil
    }()

    static func isWatched() -> Bool { isWatchedProbe?() ?? false }

    /// The display that mirrors another one (AirPlay or cable), by name.
    @MainActor
    static func mirroringTo() -> String? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return nil }
        for id in ids.prefix(Int(count)) where CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay {
            let name = NSScreen.screens.first { $0.displayID == id }?.localizedName
            return (name?.isEmpty == false ? name : nil) ?? "another display"
        }
        return nil
    }
}

// MARK: - Monitor

/// Polls whether the screen is shared, only while Nubrix runs. Nubrix never captures the screen itself.
@MainActor
final class ScreenShareMonitor: ObservableObject {
    static let shared = ScreenShareMonitor()
    static let interval: TimeInterval = 2

    @Published private(set) var state = ScreenShareState()
    var isShared: Bool { state.isShared }
    var mirroringTo: String? { state.mirroringTo }

    private var timer: Timer?

    func start() {
        guard timer == nil, !isRunningUnderXCTest else { return }
        refresh()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        // Leave the displays alone while they are being reconfigured.
        guard DisplayReconfigurationWatcher.shared.isQuiet else { return }
        let next = ScreenShareState(watched: ScreenShareReader.isWatched(), mirroringTo: ScreenShareReader.mirroringTo())
        if next != state { state = next }
    }
}

// MARK: - Alert source

@MainActor
final class ScreenShareWatcher: EverydayWatcher {
    private var tracker = ScreenShareTracker()
    private var cancellable: AnyCancellable?

    func start(emit: @escaping (EverydayAlert) -> Void) {
        stop()
        tracker = ScreenShareTracker()
        cancellable = ScreenShareMonitor.shared.$state.sink { [weak self] state in
            guard let self else { return }
            if let alert = self.tracker.update(state, notchHidden: Defaults[.hideFromScreenRecording]) { emit(alert) }
        }
    }

    func stop() {
        cancellable = nil
    }
}
