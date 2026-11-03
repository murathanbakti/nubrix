import AppKit
import SwiftUI

struct DockBadgeCountCapsule: View {
    let text: String
    var foreground: Color = .white
    var fill: Color = Color.white.opacity(0.2)

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(fill))
            .fixedSize()
    }
}

struct DockBadgeLiveActivity: View {
    @EnvironmentObject var vm: NubrixViewModel
    @ObservedObject var store = DockBadgeStore.shared

    var body: some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        HStack {
            icon(side: side)
                .frame(width: side, height: side)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            Text(store.summary.totalText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    private func icon(side: CGFloat) -> some View {
        if let top = store.summary.top, let image = SystemNotificationStore.shared.icon(for: top.bundleID) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: side * 0.8, height: side * 0.8)
        } else {
            Image(systemName: "app.badge")
                .font(.system(size: side * 0.6, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct DockBadgeRowsView: View {
    @ObservedObject var store = DockBadgeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unread in the Dock")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.gray)
                .padding(.horizontal, 2)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(store.summary.badges) { badge in
                        DockBadgeRow(badge: badge)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct DockBadgeRow: View {
    let badge: DockBadge
    @State private var hovering = false

    var body: some View {
        Button {
            SystemNotificationStore.shared.open(bundleID: badge.bundleID)
        } label: {
            HStack(spacing: 8) {
                icon
                Text(SystemNotificationStore.shared.appName(for: badge.bundleID))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                DockBadgeCountCapsule(text: badge.label)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(hovering ? 0.1 : 0.06))
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = SystemNotificationStore.shared.icon(for: badge.bundleID) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app.badge")
                .font(.system(size: 14))
                .foregroundStyle(.gray)
                .frame(width: 20, height: 20)
        }
    }
}
