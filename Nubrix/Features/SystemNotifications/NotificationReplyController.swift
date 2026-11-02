import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class NotificationReplyController: ObservableObject {
    static let shared = NotificationReplyController()

    enum Phase: Equatable {
        case checking
        case ready
        case sending
        case sent
        case needsAccess
        case missing
        case note(String)
        case unconfirmed(String)
    }

    @Published private(set) var activeRecordID: UUID?
    @Published private(set) var phase: Phase = .checking
    @Published var draft = ""
    @Published private(set) var focusToken = 0

    private struct WeakModel { weak var vm: NubrixViewModel? }

    private var models: [WeakModel] = []
    private var record: SystemNotificationRecord?
    private weak var activeModel: NubrixViewModel?
    private weak var activePanel: NubrixSkyLightPanel?
    private var activatedFrom: NSRunningApplication?
    private var didActivateApp = false
    private var holdsNotchOpen = false
    private var generation = 0
    private var cancellables = Set<AnyCancellable>()
    private var resignObserver: NSObjectProtocol?
    private var task: Task<Void, Never>?

    private var featureCancellables = Set<AnyCancellable>()

    static var isEnabled: Bool {
        Defaults[.systemNotificationsEnabled] && Defaults[.systemNotificationQuickReply]
    }

    private init() {
        Defaults.publisher(.systemNotificationsEnabled, options: [])
            .map { _ in () }
            .merge(with: Defaults.publisher(.systemNotificationQuickReply, options: []).map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard !Self.isEnabled else { return }
                self?.shutDown()
            }
            .store(in: &featureCancellables)
    }

    private func shutDown() {
        if activeRecordID != nil { end(restore: true) }
        AccessibilityGuide.shutdown()
    }

    var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSend: Bool { phase == .ready && !trimmed.isEmpty }

    func register(_ vm: NubrixViewModel) {
        models.removeAll { $0.vm == nil || $0.vm === vm }
        models.append(WeakModel(vm: vm))
    }

    func openAndBegin(record: SystemNotificationRecord, vm preferred: NubrixViewModel? = nil) {
        guard Self.isEnabled, QuickReplyAvailability.shared.isReplyAvailable(record.bundleID),
              let vm = preferred ?? preferredModel() else { return }
        NubrixCoordinator.shared.currentView = .notifications
        if vm.notchState != .open {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { vm.open() }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(vm.notchState == .open ? 120 : 380))
            begin(record: record, vm: vm)
        }
    }

    func begin(record: SystemNotificationRecord, vm preferred: NubrixViewModel? = nil) {
        guard Self.isEnabled, QuickReplyAvailability.shared.isReplyAvailable(record.bundleID) else { return }
        if activeRecordID != nil { end(restore: true) }
        guard let vm = preferred ?? preferredModel() else { return }
        generation += 1
        let current = generation
        self.record = record
        activeModel = vm
        draft = ""
        phase = .checking
        withAnimation(.smooth) { activeRecordID = record.id }
        acquireKey(for: vm)

        vm.$notchState
            .dropFirst()
            .filter { $0 == .closed }
            .sink { [weak self] _ in self?.cancel() }
            .store(in: &cancellables)
        NubrixCoordinator.shared.$currentView
            .dropFirst()
            .filter { $0 != .notifications }
            .sink { [weak self] _ in self?.cancel() }
            .store(in: &cancellables)

        task?.cancel()
        task = Task { @MainActor in
            async let accessCheck = XPCHelperClient.shared.isAccessibilityAuthorized()
            async let existsCheck = XPCHelperClient.shared.notificationExists(recID: record.recID)
            let (access, exists) = await (accessCheck, existsCheck)
            guard current == generation, !Task.isCancelled else { return }
            if exists == false {
                withAnimation(.smooth) { phase = .missing }
            } else if access != true {
                withAnimation(.smooth) { phase = .needsAccess }
            } else {
                withAnimation(.smooth) { phase = .ready }
                try? await Task.sleep(for: .milliseconds(120))
                guard current == generation else { return }
                activePanel?.makeKey()
                focusToken += 1
            }
        }
    }

    func cancel() {
        guard activeRecordID != nil else { return }
        if phase == .sending || phase == .sent { return }
        end(restore: true)
    }

    func requestAccess() {
        guard let record else { return }
        end(restore: false)
        AccessibilityGuide.begin(resume: record)
    }

    func openApp() {
        guard let record else { return }
        end(restore: false)
        SystemNotificationStore.shared.open(bundleID: record.bundleID)
    }

    func send() {
        guard Self.isEnabled, canSend, let record else { return }
        let message = trimmed
        let current = generation
        phase = .sending
        let store = SystemNotificationStore.shared
        task = Task { @MainActor in
            let status = await store.reply(to: record, text: message)
            guard current == generation else { return }
            switch status {
            case .sent:
                withAnimation(.smooth) { phase = .sent }
                try? await Task.sleep(for: .seconds(1))
                guard current == generation else { return }
                end(restore: true)
                withAnimation(.smooth) { store.removeRecord(record.id) }
            case .noAccess:
                withAnimation(.smooth) { phase = .needsAccess }
            case .notFound:
                await finish("Couldn't find this notification in Notification Center. Text copied, paste it in \(record.appName).", status, record, current)
            case .failed:
                await finish("Couldn't reply from the notch. Text copied, paste it in \(record.appName).", status, record, current)
            case .unsupported:
                await finish("\(record.appName) has no reply action in its notifications. Text copied.", status, record, current)
            case .gone:
                await finish("This notification was cleared from Notification Center. Text copied.", status, record, current)
            case .previewsHidden:
                await QuickReplyAvailability.shared.markHidden(record.bundleID)
                await finish("Previews are off for \(record.appName), so your text was copied.", status, record, current)
            case .unconfirmed:
                withAnimation(.smooth) { phase = .unconfirmed("Sent, but Nubrix couldn't confirm it. Text copied, check \(record.appName).") }
            }
        }
    }

    private func finish(_ message: String, _ status: SystemNotificationReplyStatus,
                        _ record: SystemNotificationRecord, _ current: Int) async {
        withAnimation(.smooth) { phase = .note(message) }
        try? await Task.sleep(for: .seconds(2.5))
        guard current == generation else { return }
        end(restore: false)
        SystemNotificationStore.shared.finishReply(status, record: record)
    }

    private func preferredModel() -> NubrixViewModel? {
        models.removeAll { $0.vm == nil }
        let live = models.compactMap(\.vm)
        let selected = NubrixCoordinator.shared.selectedScreenUUID
        return live.first { $0.notchState == .open && $0.screenUUID == selected }
            ?? live.first { $0.screenUUID == selected }
            ?? live.first { $0.notchState == .open }
            ?? live.first
    }

    private func panel(for vm: NubrixViewModel) -> NubrixSkyLightPanel? {
        let panels = NSApp.windows.compactMap { $0 as? NubrixSkyLightPanel }
        if let uuid = vm.screenUUID, let screen = NSScreen.screen(withUUID: uuid),
           let match = panels.first(where: { $0.screen == screen }) {
            return match
        }
        return panels.first
    }

    private func acquireKey(for vm: NubrixViewModel) {
        guard let panel = panel(for: vm) else { return }
        activePanel = panel
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            activatedFrom = front
            didActivateApp = true
        }
        panel.allowsKeyInput = true
        if !holdsNotchOpen {
            SharingStateManager.shared.beginInteraction()
            holdsNotchOpen = true
        }
        NSApp.activate()
        panel.makeKey()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeRecordID != nil, self.phase != .sending, self.phase != .sent else { return }
                if case .note = self.phase { return }
                if case .unconfirmed = self.phase { return }
                if self.activePanel?.isKeyWindow == true { return }
                self.cancel()
            }
        }
    }

    private func end(restore: Bool) {
        generation += 1
        task?.cancel()
        task = nil
        cancellables.removeAll()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        if let panel = activePanel {
            panel.allowsKeyInput = false
            if panel.isKeyWindow { panel.resignKey() }
        }
        activePanel = nil
        activeModel = nil
        record = nil
        draft = ""
        withAnimation(.smooth) { activeRecordID = nil }
        phase = .checking
        if holdsNotchOpen {
            holdsNotchOpen = false
            SharingStateManager.shared.endInteraction()
        }
        let previous = activatedFrom
        let didActivate = didActivateApp
        activatedFrom = nil
        didActivateApp = false
        guard restore, didActivate, let previous, !previous.isTerminated, NSApp.isActive,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        else { return }
        previous.activate()
    }
}
