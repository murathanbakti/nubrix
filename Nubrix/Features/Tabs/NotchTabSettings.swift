import Defaults
import SwiftUI

struct NotchTabSettings: View {
    @ObservedObject private var layout = NotchTabLayout.shared
    @ObservedObject private var coordinator = NubrixCoordinator.shared
    @Default(.nubrixShelf) private var shelfEnabled
    @Default(.vitrinEnabled) private var vitrinEnabled
    @Default(.devEnabled) private var devEnabled
    @Default(.systemNotificationsEnabled) private var notificationsEnabled
    @Default(.dockBadgesEnabled) private var badgesEnabled
    @Default(.claudeEnabled) private var claudeEnabled
    @Default(.notchHiddenTabs) private var hiddenTabs

    var body: some View {
        Form {
            Section {
                ForEach(layout.orderedTabs) { tab in
                    row(for: tab)
                }
                .onMove { source, destination in
                    layout.move(from: source, to: destination)
                }
            } header: {
                Text("Order")
            } footer: {
                SettingsFooter("Drag to reorder. Hiding a tab only removes it from the notch; the feature keeps running. To stop a feature, turn it off in its own settings.")
            }

            Section {
                Toggle("Always show tabs", isOn: $coordinator.alwaysShowTabs)
                Toggle("Remember last tab", isOn: $coordinator.openLastTabByDefault)
            } header: {
                Text("Behavior")
            }

            Section {
                Button("Restore defaults") {
                    layout.resetToDefault()
                }
            }
        }
        .settingsPage(.tabs)
    }

    private func row(for tab: TabModel) -> some View {
        let featureOn = isFeatureEnabled(tab.view)
        let visible = layout.isVisible(tab.view)
        let isOn = featureOn ? visible : !hiddenTabs.contains(tab.view)
        let onlyOne = featureOn && layout.isOnlyVisible(tab.view)
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            Image(systemName: tab.icon)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.label)
                if !featureOn, let hint = NotchTabCatalog.featureOffHint(for: tab.view) {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("Show", isOn: Binding(
                get: { isOn },
                set: { layout.setHidden(tab.view, !$0) }
            ))
            .toggleStyle(.switch)
            .disabled(!featureOn || onlyOne)
        }
        .foregroundStyle(featureOn ? .primary : .secondary)
        .opacity(featureOn ? 1 : 0.55)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func isFeatureEnabled(_ view: NotchViews) -> Bool {
        switch view {
        case .home, .controls: return true
        case .shelf: return shelfEnabled
        case .vitrin: return vitrinEnabled
        case .agents: return claudeEnabled
        case .dev: return devEnabled
        case .notifications: return notificationsEnabled || badgesEnabled
        }
    }
}
