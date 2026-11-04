//
//  SettingsView.swift
//  Nubrix
//
//  Created by Richard Kunkli on 07/08/2024.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accentColorUpdateTrigger = UUID()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTabGroup.allCases) { group in
                    if let title = group.title {
                        Section(title) { rows(in: group) }
                    } else {
                        Section { rows(in: group) }
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .tint(.effectiveAccent)
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(200)
        } detail: {
            SettingsDetail(tab: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("")
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .tint(.effectiveAccent)
        .id(accentColorUpdateTrigger)
        .onReceive(SettingsNavigation.shared.$requested) { requested in
            guard let requested else { return }
            selectedTab = requested
            SettingsNavigation.shared.requested = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("AccentColorChanged"))) { _ in
            accentColorUpdateTrigger = UUID()
        }
    }

    private func rows(in group: SettingsTabGroup) -> some View {
        ForEach(group.tabs) { tab in
            NavigationLink(value: tab) {
                Label(tab.title, systemImage: tab.symbol)
            }
        }
    }
}

private struct SettingsDetail: View {
    let tab: SettingsTab

    var body: some View {
        switch tab {
        case .general: GeneralSettings()
        case .appearance: AppearanceSettings()
        case .permissions: PermissionsSettings()
        case .claudeCode: ClaudeCodeSettings()
        case .github: GitHubSettings()
        case .dev: DevSettings()
        case .tabs: NotchTabSettings()
        case .notifications: InboxSettings()
        case .everyday: EverydaySettings()
        case .vitrin: VitrinSettings()
        case .media: MediaSettings()
        case .calendar: CalendarSettings()
        case .shelf: ShelfSettings()
        case .huds: HUDSettings()
        case .shortcuts: ShortcutsSettings()
        case .advanced: AdvancedSettings()
        case .about: AboutSettings()
        }
    }
}
