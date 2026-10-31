import Defaults
import SwiftUI

struct DevNotification: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let title: String?
    let style: DevNotificationStyle
    let duration: Double
    let date: Date
}

extension DevNotificationStyle {
    var tint: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return Color(red: 0.35, green: 0.65, blue: 1.0)
        case .warning: return .orange
        }
    }

    var symbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
final class DevNotificationStore: ObservableObject {
    static let shared = DevNotificationStore()
    static let capacity = 50

    @Published private(set) var notifications: [DevNotification] = []
    @Published private(set) var banner: DevNotification?

    private var bannerTask: Task<Void, Never>?

    private init() {}

    func post(_ request: DevNotifyRequest) {
        guard Defaults[.devEnabled] else { return }
        let notification = DevNotification(
            message: request.message,
            title: request.title,
            style: request.style,
            duration: request.duration,
            date: Date()
        )
        notifications.insert(notification, at: 0)
        if notifications.count > Self.capacity { notifications.removeLast(notifications.count - Self.capacity) }
        NubrixInbox.shared.notchctl(title: request.title, message: request.message)
        show(notification)
    }

    func clear() {
        notifications.removeAll()
        dismissBanner()
    }

    func remove(_ id: UUID) {
        notifications.removeAll { $0.id == id }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        guard banner != nil else { return }
        withAnimation(.smooth) { banner = nil }
    }

    private func show(_ notification: DevNotification) {
        AgentSessionStore.shared.dismissBanner()
        ScreenshotBannerStore.shared.dismissBanner()
        bannerTask?.cancel()
        withAnimation(.smooth) { banner = notification }
        let duration = notification.duration
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }
}
