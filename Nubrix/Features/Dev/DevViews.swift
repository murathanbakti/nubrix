import AppKit
import SwiftUI

struct DevBannerView: View {
    @EnvironmentObject var vm: NubrixViewModel
    let banner: DevNotification

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: banner.style.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(banner.style.tint)
                Text(banner.title ?? "notchctl")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 140, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(banner.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(banner.style.tint)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 170, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct DevTabView: View {
    @ObservedObject var monitor = DevPortMonitor.shared
    @ObservedObject var store = DevNotificationStore.shared
    @State private var copiedPort: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            serversColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            notificationsColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.top, 4)
        .onAppear {
            DevPortMonitor.shared.setActive("tab", true)
        }
        .onDisappear {
            DevPortMonitor.shared.setActive("tab", false)
        }
    }

    private var serversColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dev servers")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)
                .padding(.horizontal, 4)
            if monitor.servers.isEmpty {
                placeholder(icon: "bolt.horizontal", text: "Nothing listening", detail: "Watching localhost ports.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(monitor.servers) { server in
                            serverRow(server)
                        }
                    }
                }
            }
        }
    }

    private func serverRow(_ server: DevServer) -> some View {
        Button {
            activate(server)
        } label: {
            HStack(spacing: 8) {
                Circle().fill(.green).frame(width: 7, height: 7)
                Text(server.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(copiedPort == server.port ? "Copied" : ":\(server.port)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(copiedPort == server.port ? Color.green : Color.gray)
                Image(systemName: server.isDatabase ? "doc.on.doc" : "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(server.isDatabase ? "Copy \(server.address)" : "Open http://\(server.address)")
    }

    private func activate(_ server: DevServer) {
        if server.isDatabase {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(server.address, forType: .string)
            copiedPort = server.port
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copiedPort == server.port { copiedPort = nil }
            }
        } else if let url = URL(string: "http://\(server.address)") {
            NSWorkspace.shared.open(url)
        }
    }

    private var notificationsColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Notifications")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.gray)
                Spacer()
                if !store.notifications.isEmpty {
                    Button("Clear") { withAnimation(.smooth) { store.clear() } }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
            }
            .padding(.horizontal, 4)
            if store.notifications.isEmpty {
                placeholder(icon: "bell", text: "No notifications", detail: "notchctl notify \"Done\"")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(store.notifications) { item in
                            DevNotificationRow(item: item)
                        }
                    }
                }
            }
        }
    }

    private func placeholder(icon: String, text: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.gray)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DevNotificationRow: View {
    let item: DevNotification
    @ObservedObject var store = DevNotificationStore.shared
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.style.symbol)
                .font(.system(size: 13))
                .foregroundStyle(item.style.tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                if let title = item.title {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Text(item.message)
                    .font(.system(size: 11))
                    .foregroundStyle(item.title == nil ? .white : .gray)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            if hovering {
                Button {
                    withAnimation(.smooth) { store.remove(item.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.age(from: item.date, to: context.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
        .onHover { hovering = $0 }
    }

    private static func age(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
