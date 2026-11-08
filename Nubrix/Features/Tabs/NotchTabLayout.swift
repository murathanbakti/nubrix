import Combine
import Defaults
import Foundation
import SwiftUI

extension Defaults.Keys {
    static let notchTabOrder = Key<[NotchViews]>("notchTabOrder", default: NotchViews.allCases)
    static let notchHiddenTabs = Key<[NotchViews]>("notchHiddenTabs", default: [])
}

struct TabModel: Identifiable, Equatable {
    let label: String
    let icon: String
    let view: NotchViews
    var id: NotchViews { view }
}

enum NotchTabCatalog {
    static let all: [TabModel] = [
        TabModel(label: "Home", icon: "house.fill", view: .home),
        TabModel(label: "Controls", icon: "slider.horizontal.3", view: .controls),
        TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
        TabModel(label: "Vitrin", icon: "square.stack.3d.up.fill", view: .vitrin),
        TabModel(label: "Claude", icon: "sparkle", view: .agents),
        TabModel(label: "Dev", icon: "terminal.fill", view: .dev),
        TabModel(label: "Notifications", icon: "bell.fill", view: .notifications)
    ]

    static func model(for view: NotchViews) -> TabModel {
        all.first { $0.view == view } ?? TabModel(label: view.rawValue.capitalized, icon: "square", view: view)
    }

    static func settingsTab(for view: NotchViews) -> SettingsTab? {
        switch view {
        case .home, .controls: return nil
        case .shelf: return .shelf
        case .vitrin: return .vitrin
        case .agents: return .claudeCode
        case .dev: return .dev
        case .notifications: return .notifications
        }
    }

    static func featureOffHint(for view: NotchViews) -> String? {
        settingsTab(for: view).map { "Turned off in Settings → \($0.title)." }
    }
}

@MainActor
final class NotchTabLayout: ObservableObject {
    static let shared = NotchTabLayout()

    @Published private(set) var orderedTabs: [TabModel]
    @Published private(set) var visibleTabs: [TabModel]

    let didChange = PassthroughSubject<Void, Never>()

    private var cancellable: AnyCancellable?

    private init() {
        orderedTabs = Self.computeOrdered(Defaults[.notchTabOrder])
        visibleTabs = Self.computeVisible(order: Defaults[.notchTabOrder], hidden: Defaults[.notchHiddenTabs])
        cancellable = Defaults.publisher(
            keys: Defaults.Keys.notchTabOrder, Defaults.Keys.notchHiddenTabs,
            Defaults.Keys.nubrixShelf, Defaults.Keys.vitrinEnabled, Defaults.Keys.devEnabled,
            Defaults.Keys.systemNotificationsEnabled, Defaults.Keys.dockBadgesEnabled, Defaults.Keys.claudeEnabled,
            options: []
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.refresh() }
    }

    nonisolated static func isFeatureEnabled(_ view: NotchViews) -> Bool {
        switch view {
        case .home, .controls: return true
        case .shelf: return Defaults[.nubrixShelf]
        case .vitrin: return Defaults[.vitrinEnabled]
        case .agents: return Defaults[.claudeEnabled]
        case .dev: return Defaults[.devEnabled]
        case .notifications: return Defaults[.systemNotificationsEnabled] || Defaults[.dockBadgesEnabled]
        }
    }

    nonisolated static func computeOrdered(_ saved: [NotchViews]) -> [TabModel] {
        var seen = Set<NotchViews>()
        var ids = saved.filter { seen.insert($0).inserted }
        ids.append(contentsOf: NotchViews.allCases.filter { !seen.contains($0) })
        return ids.map(NotchTabCatalog.model(for:))
    }

    nonisolated static func computeVisible(order: [NotchViews], hidden: [NotchViews]) -> [TabModel] {
        let ordered = computeOrdered(order)
        let hiddenSet = Set(hidden)
        let enabled = ordered.filter { isFeatureEnabled($0.view) }
        let shown = enabled.filter { !hiddenSet.contains($0.view) }
        if !shown.isEmpty { return shown }
        return enabled.first.map { [$0] } ?? [NotchTabCatalog.model(for: .home)]
    }

    private func refresh() {
        let order = Defaults[.notchTabOrder]
        let ordered = Self.computeOrdered(order)
        let visible = Self.computeVisible(order: order, hidden: Defaults[.notchHiddenTabs])
        guard ordered != orderedTabs || visible != visibleTabs else { return }
        if ordered != orderedTabs { orderedTabs = ordered }
        if visible != visibleTabs { visibleTabs = visible }
        didChange.send()
    }

    private var currentVisible: [TabModel] {
        Self.computeVisible(order: Defaults[.notchTabOrder], hidden: Defaults[.notchHiddenTabs])
    }

    var firstVisible: NotchViews { currentVisible.first?.view ?? .home }

    func isFeatureEnabled(_ view: NotchViews) -> Bool { Self.isFeatureEnabled(view) }

    func isVisible(_ view: NotchViews) -> Bool { currentVisible.contains { $0.view == view } }

    func isHidden(_ view: NotchViews) -> Bool { Defaults[.notchHiddenTabs].contains(view) }

    func isOnlyVisible(_ view: NotchViews) -> Bool {
        let visible = currentVisible
        return visible.count == 1 && visible[0].view == view
    }

    func setHidden(_ view: NotchViews, _ hidden: Bool) {
        var set = Set(Defaults[.notchHiddenTabs])
        if hidden {
            let remaining = NotchViews.allCases.filter { Self.isFeatureEnabled($0) && $0 != view && !set.contains($0) }
            if Self.isFeatureEnabled(view) && remaining.isEmpty { return }
            set.insert(view)
        } else {
            set.remove(view)
        }
        Defaults[.notchHiddenTabs] = NotchViews.allCases.filter { set.contains($0) }
    }

    func move(from source: IndexSet, to destination: Int) {
        var ids = Self.computeOrdered(Defaults[.notchTabOrder]).map(\.view)
        ids.move(fromOffsets: source, toOffset: destination)
        Defaults[.notchTabOrder] = ids
    }

    func resetToDefault() {
        Defaults[.notchTabOrder] = NotchViews.allCases
        Defaults[.notchHiddenTabs] = []
    }
}
