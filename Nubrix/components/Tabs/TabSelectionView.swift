//
//  TabSelectionView.swift
//  Nubrix
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Vitrin", icon: "square.stack.3d.up.fill", view: .vitrin),
    TabModel(label: "Claude", icon: "sparkle", view: .agents),
    TabModel(label: "Dev", icon: "terminal.fill", view: .dev),
    TabModel(label: "Notifications", icon: "bell.fill", view: .notifications)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = NubrixCoordinator.shared
    @ObservedObject var inbox = NubrixInbox.shared
    @Namespace var animation
    var body: some View {
        let visibleTabs = tabs.filter { ($0.view != .shelf || Defaults[.nubrixShelf]) && ($0.view != .vitrin || Defaults[.vitrinEnabled]) && ($0.view != .dev || Defaults[.devEnabled]) && ($0.view != .notifications || Defaults[.systemNotificationsEnabled]) }
        let padding: CGFloat = visibleTabs.count >= 6 ? 6 : 8
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view, badge: inbox.severity(for: tab.view)?.tint, horizontalPadding: padding) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
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
