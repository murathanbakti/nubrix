import AppKit
import Combine
import Defaults
import SwiftUI

enum EverydaySource: CaseIterable {
    case soundOutput, drives, micCamera, internet, screenShare

    var key: Defaults.Key<Bool> {
        switch self {
        case .soundOutput: .everydaySoundOutput
        case .drives: .everydayDrives
        case .micCamera: .everydayMicCamera
        case .internet: .everydayInternet
        case .screenShare: .everydayScreenShare
        }
    }

    @MainActor
    func makeWatcher() -> EverydayWatcher {
        switch self {
        case .soundOutput: SoundOutputWatcher()
        case .drives: DriveWatcher()
        case .micCamera: MicCameraWatcher()
        case .internet: InternetWatcher()
        case .screenShare: ScreenShareWatcher()
        }
    }
}

/// Shows one everyday alert at a time. A newer alert replaces the one on screen.
@MainActor
final class EverydayAlertStore: ObservableObject {
    static let shared = EverydayAlertStore(observesOtherBanners: true)
    static let animation = Animation.spring(response: 0.38, dampingFraction: 0.82)

    @Published private(set) var banner: EverydayAlert?

    private let duration: Double
    private var bannerTask: Task<Void, Never>?
    private var watchers: [EverydaySource: EverydayWatcher] = [:]
    private var observing = false
    private var cancellables = Set<AnyCancellable>()
    private let observesOtherBanners: Bool

    init(duration: Double = 4, observesOtherBanners: Bool = false) {
        self.duration = duration
        self.observesOtherBanners = observesOtherBanners
        guard observesOtherBanners else { return }
        // A system notification or a device battery banner takes over the notch.
        SystemNotificationStore.shared.$banner
            .dropFirst()
            .sink { [weak self] value in
                if value != nil { Task { @MainActor in self?.dismissBanner() } }
            }
            .store(in: &cancellables)
        DeviceBatteryStore.shared.$banner
            .dropFirst()
            .sink { [weak self] value in
                if value != nil { Task { @MainActor in self?.dismissBanner() } }
            }
            .store(in: &cancellables)
    }

    /// Safe to call more than once.
    func start() {
        if !observing {
            observing = true
            for source in EverydaySource.allCases {
                Defaults.publisher(source.key, options: [])
                    .sink { [weak self] _ in Task { @MainActor in self?.start() } }
                    .store(in: &cancellables)
            }
        }
        for source in EverydaySource.allCases {
            let allowed = DeviceBatteryStore.canRun(enabled: Defaults[source.key], firstLaunch: UserDefaults.standard.object(forKey: "firstLaunch"))
            if allowed, watchers[source] == nil {
                let watcher = source.makeWatcher()
                watchers[source] = watcher
                watcher.start { [weak self] alert in self?.show(alert) }
            } else if !allowed, let watcher = watchers.removeValue(forKey: source) {
                watcher.stop()
            }
        }
    }

    func stop() {
        for watcher in watchers.values { watcher.stop() }
        watchers = [:]
        dismissBanner()
    }

    func show(_ alert: EverydayAlert) {
        bannerTask?.cancel()
        withAnimation(Self.animation) { banner = alert }
        let shownID = alert.id
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, self?.banner?.id == shownID else { return }
            self?.dismissBanner()
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        guard banner != nil else { return }
        withAnimation(Self.animation) { banner = nil }
    }

    func perform(_ action: EverydayAlert.Action) {
        switch action {
        case .showInFinder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        case .eject(let url):
            let name = FileManager.default.displayName(atPath: url.path)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                } catch {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self.show(DriveAlerts.ejectFailed(name: name, url: url))
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }
        }
    }
}
