import Combine
import Defaults
import Foundation

@MainActor
final class QuickReplyAvailability: ObservableObject {
    static let shared = QuickReplyAvailability()

    @Published private(set) var hidden: [String: String] = Defaults[.quickReplyPreviewsHidden]

    private var lastRefresh: [String: Date] = [:]

    private init() {}

    func isReplyAvailable(_ bundleID: String) -> Bool {
        Defaults[.systemNotificationQuickReply] && hidden[bundleID] == nil
    }

    func isHidden(_ bundleID: String) -> Bool { hidden[bundleID] != nil }

    func markHidden(_ bundleID: String) async {
        let fingerprint = await XPCHelperClient.shared.notificationPreviewFingerprint(bundleID: bundleID) ?? "?"
        store(bundleID, fingerprint)
    }

    func clear(_ bundleID: String) {
        store(bundleID, nil)
        lastRefresh[bundleID] = nil
    }

    func refresh(_ bundleIDs: [String], force: Bool = false) {
        for bundleID in Set(bundleIDs) where hidden[bundleID] != nil {
            if !force, let last = lastRefresh[bundleID], Date().timeIntervalSince(last) < 30 { continue }
            lastRefresh[bundleID] = Date()
            Task { @MainActor in
                let current = await XPCHelperClient.shared.notificationPreviewFingerprint(bundleID: bundleID)
                guard let stored = hidden[bundleID], let current, stored != "?" else { return }
                if current != stored { store(bundleID, nil) }
            }
        }
    }

    private func store(_ bundleID: String, _ fingerprint: String?) {
        var copy = hidden
        copy[bundleID] = fingerprint
        hidden = copy
        Defaults[.quickReplyPreviewsHidden] = copy
    }
}
