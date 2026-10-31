import AppKit
import Combine
import Defaults

private final class ScreenshotFolderMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.nubrix.vitrin.screenshots", qos: .utility)
    private let path: String
    private let startedAt = Date()
    private let onReady: @Sendable (String) -> Void
    private let onLost: @Sendable () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var known: Set<String> = []
    private var pendingScan: DispatchWorkItem?
    private var tracking: [String: Task<Void, Never>] = [:]
    private var cancelled = false

    init?(path: String, onReady: @escaping @Sendable (String) -> Void, onLost: @escaping @Sendable () -> Void) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.path = path
        self.onReady = onReady
        self.onLost = onLost
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .revoke], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, let source = self.source else { return }
            self.handle(source.data)
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        queue.async { [self] in
            known = Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
        }
        source.resume()
    }

    func stop() {
        queue.async { [self] in
            cancelled = true
            pendingScan?.cancel()
            pendingScan = nil
            tracking.values.forEach { $0.cancel() }
            tracking.removeAll()
            source?.cancel()
            source = nil
        }
    }

    private func handle(_ event: DispatchSource.FileSystemEvent) {
        guard !cancelled else { return }
        if !event.isDisjoint(with: [.delete, .rename, .revoke]) {
            onLost()
            return
        }
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work
        queue.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
    }

    private func scan() {
        guard !cancelled else { return }
        guard let current = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            onLost()
            return
        }
        let fresh = ScreenshotDetection.newCandidates(current: current, known: known)
        known = Set(current)
        for name in fresh where tracking[name] == nil {
            track(name)
        }
    }

    private func track(_ name: String) {
        let full = (path as NSString).appendingPathComponent(name)
        let start = startedAt
        tracking[name] = Task.detached(priority: .utility) { [weak self] in
            var candidate = ScreenshotCandidate(path: full, watchStart: start)
            var outcome = ScreenshotVerdict.waiting
            for _ in 0..<ScreenshotWatcher.maxPolls {
                try? await Task.sleep(for: ScreenshotWatcher.pollInterval)
                guard !Task.isCancelled else { return }
                outcome = candidate.poll()
                if outcome != .waiting { break }
            }
            self?.finish(name, path: full, ready: outcome == .ready)
        }
    }

    private func finish(_ name: String, path: String, ready: Bool) {
        queue.async { [self] in
            guard !cancelled else { return }
            tracking[name] = nil
            if ready { onReady(path) }
        }
    }
}

@MainActor
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    nonisolated static let pollInterval: Duration = .milliseconds(250)
    nonisolated static let maxPolls = 48

    private var monitor: ScreenshotFolderMonitor?
    private var watchedPath: String?
    private var recoverTask: Task<Void, Never>?

    private init() {}

    var isRunning: Bool { monitor != nil }

    private var shouldRun: Bool {
        Defaults[.vitrinEnabled] && Defaults[.vitrinCaptureImages] && Defaults[.vitrinCaptureScreenshots]
            && ClipStore.shared.isReady && ScreenshotAccess.shared.hasAccess
    }

    func refresh() {
        guard shouldRun, let folder = ScreenshotAccess.shared.folder else {
            stop()
            return
        }
        if isRunning, watchedPath == folder.path { return }
        stop()
        begin(folder)
    }

    func stop() {
        recoverTask?.cancel()
        recoverTask = nil
        monitor?.stop()
        monitor = nil
        watchedPath = nil
    }

    private func begin(_ folder: URL) {
        let monitor = ScreenshotFolderMonitor(
            path: folder.path,
            onReady: { path in
                Task { @MainActor in ScreenshotWatcher.shared.importFile(at: path) }
            },
            onLost: {
                Task { @MainActor in ScreenshotWatcher.shared.recoverFolder() }
            }
        )
        guard let monitor else {
            recoverFolder()
            return
        }
        watchedPath = folder.path
        self.monitor = monitor
    }

    private func recoverFolder() {
        stop()
        ScreenshotAccess.shared.restore()
        recoverTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.recoverTask = nil
            self?.refresh()
        }
    }

    private func importFile(at path: String) {
        guard shouldRun else { return }
        Task.detached(priority: .utility) {
            let url = URL(fileURLWithPath: path)
            guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
                  size > 0, size <= ClipImageProcessor.maximumBytes,
                  let data = try? Data(contentsOf: url),
                  let prepared = ClipImageProcessor.prepare(data) else { return }
            guard let item = await ClipStore.shared.addImage(prepared, source: ScreenshotDetection.sourceID) else { return }
            await MainActor.run {
                guard Defaults[.vitrinScreenshotPreview] else { return }
                ScreenshotBannerStore.shared.show(item)
            }
        }
    }
}
