import SwiftUI

enum SettingsTabGroup: CaseIterable, Identifiable {
    case main
    case developer
    case notch
    case app

    var id: Self { self }

    var title: String? {
        switch self {
        case .main, .app: return nil
        case .developer: return "Developer"
        case .notch: return "Notch"
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.group == self }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case appearance
    case permissions
    case claudeCode
    case github
    case dev
    case tabs
    case notifications
    case vitrin
    case media
    case calendar
    case shelf
    case huds
    case shortcuts
    case advanced
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .permissions: return "Permissions"
        case .claudeCode: return "Claude Code"
        case .github: return "GitHub"
        case .dev: return "Dev"
        case .tabs: return "Tabs"
        case .notifications: return "Notifications"
        case .vitrin: return "Vitrin"
        case .media: return "Media"
        case .calendar: return "Calendar"
        case .shelf: return "Shelf"
        case .huds: return "HUDs"
        case .shortcuts: return "Shortcuts"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gear"
        case .appearance: return "eye"
        case .permissions: return "lock.shield"
        case .claudeCode: return "sparkle"
        case .github: return "arrow.triangle.branch"
        case .dev: return "terminal.fill"
        case .tabs: return "rectangle.split.3x1"
        case .notifications: return "bell.badge.fill"
        case .vitrin: return "square.stack.3d.up.fill"
        case .media: return "play.laptopcomputer"
        case .calendar: return "calendar"
        case .shelf: return "books.vertical"
        case .huds: return "dial.medium.fill"
        case .shortcuts: return "keyboard"
        case .advanced: return "gearshape.2"
        case .about: return "info.circle"
        }
    }

    var group: SettingsTabGroup {
        switch self {
        case .general, .appearance, .permissions: return .main
        case .claudeCode, .github, .dev: return .developer
        case .tabs, .notifications, .vitrin, .media, .calendar, .shelf, .huds: return .notch
        case .shortcuts, .advanced, .about: return .app
        }
    }

    init?(title: String) {
        guard let tab = Self.allCases.first(where: { $0.title == title }) else { return nil }
        self = tab
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var requested: SettingsTab?
    private init() {}

    func open(_ tab: SettingsTab) {
        requested = tab
        SettingsWindowController.shared.showWindow()
    }

    func open(_ title: String) {
        open(SettingsTab(title: title) ?? .general)
    }
}

enum SettingsLinks {
    static let claudeCodeGuide = URL(string: "https://github.com/murathanbakti/nubrix/blob/main/docs/nubrix/CLAUDE-CODE.md")!
    static let permissionsAndSettings = URL(string: "https://github.com/murathanbakti/nubrix/blob/main/docs/nubrix/PERMISSIONS-AND-SETTINGS.md")!
    static let notificationsGuide = URL(string: "https://github.com/murathanbakti/nubrix/blob/main/docs/nubrix/PERMISSIONS-AND-SETTINGS.md#notifications")!
}
