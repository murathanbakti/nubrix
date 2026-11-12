//
//  TabSelectionView.swift
//  Nubrix
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabSelectionView: View {
    @ObservedObject var coordinator = NubrixCoordinator.shared
    @ObservedObject var inbox = NubrixInbox.shared
    @ObservedObject var dockBadges = DockBadgeStore.shared
    @ObservedObject var layout = NotchTabLayout.shared
    @Environment(\.nubrixPalette) private var palette
    @Namespace var animation
    var body: some View {
        let visibleTabs = layout.visibleTabs
        let padding: CGFloat = visibleTabs.count >= 6 ? 6 : 8
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view, badge: inbox.severity(for: tab.view)?.tint ?? (tab.view == .notifications && dockBadges.total > 0 ? InboxSeverity.notice.tint : nil), horizontalPadding: padding) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? palette.icon : palette.secondary)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? palette.surfaceStrong : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? palette.surfaceStrong : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    NubrixHeader().environmentObject(NubrixViewModel())
}
