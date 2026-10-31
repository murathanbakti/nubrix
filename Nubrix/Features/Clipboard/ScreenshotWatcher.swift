import AppKit
import Combine
import Defaults

@MainActor
final class ScreenshotWatcher {
    static let shared = ScreenshotWatcher()

    static let debounce: Duration = .milliseconds(300)
    static let pollInterval: Duration = .milliseconds(250)
    static let maxPolls = 48

    private var source: DispatchSourceFileSystemObject?
    private var watchedPath: String?
    private var known: Set<String> = []
    private var startedAt = Date()
    private var scanTask: Task<Void, Never>?
    private var tracking: [String: Task<Void, Never>] = [:]
    private var recoverTask: Task<Void, Never>?

    private init() {}

    var isRunning: Bool { source != nil }

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
        scanTask?.cancel()
        scanTask = nil
        recoverTask?.cancel()
        recoverTask = nil
        tracking.values.forEach { $0.cancel() }
        tracking.removeAll()
        source?.cancel()
        source = nil
        watchedPath = nil
        known = []
    }

    private func begin(_ folder: URL) {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            recoverFolder()
            return
        }
        startedAt = Date()
        known = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        watchedPath = folder.path
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .revoke], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let event = source.data
            MainActor.assumeIsolated {
                if !event.isDisjoint(with: [.delete, .rename, .revoke]) {
                    self.recoverFolder()
                } else {
                    self.scheduleScan()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        self.source = source
        source.resume()
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

    private func scheduleScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.scan()
        }
    }

    private func scan() {
        guard let watchedPath else { return }
        guard let current = try? FileManager.default.contentsOfDirectory(atPath: watchedPath) else {
            recoverFolder()
            return
        }
        let fresh = ScreenshotDetection.newCandidates(current: current, known: known)
        known = Set(current)
        for name in fresh where tracking[name] == nil {
            track((watchedPath as NSString).appendingPathComponent(name), name: name)
        }
    }

    private func track(_ path: String, name: String) {
        let start = startedAt
        tracking[name] = Task { [weak self] in
            var candidate = ScreenshotCandidate(path: path, watchStart: start)
            var outcome = ScreenshotVerdict.waiting
            for _ in 0..<Self.maxPolls {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                outcome = candidate.poll()
                if outcome != .waiting { break }
            }
            self?.tracking[name] = nil
            guard outcome == .ready else { return }
            self?.importFile(at: path)
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
            await MainActor.run {
                guard let id = ClipStore.shared.addImage(prepared, source: ScreenshotDetection.sourceID) else { return }
                guard Defaults[.vitrinScreenshotPreview],
                      let item = ClipStore.shared.items.first(where: { $0.id == id }) else { return }
                ScreenshotBannerStore.shared.show(item)
            }
        }
    }
}
