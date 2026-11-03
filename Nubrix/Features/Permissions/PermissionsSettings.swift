import AppKit
import SwiftUI

enum PermissionRowAction: Equatable {
    case none
    case grant
    case openSettings
}

@MainActor
final class PermissionsSettingsModel: ObservableObject {
    static let rows: [AppPermission] = [
        .accessibility,
        .fullDiskAccess,
        .camera,
        .calendar,
        .automation(.music),
        .automation(.spotify),
        .automation(.terminal),
        .automation(.iterm),
        .pasteboard
    ]

    @Published private(set) var statuses: [AppPermission: PermissionStatus] = [:]

    private let client: any PermissionClient

    init(client: (any PermissionClient)? = nil) {
        self.client = client ?? Permissions.client
    }

    func refresh() async {
        var result: [AppPermission: PermissionStatus] = [:]
        for permission in Self.rows {
            result[permission] = await client.status(permission)
        }
        statuses = result
    }

    func perform(_ permission: AppPermission) async {
        let status = statuses[permission] ?? .notDetermined
        switch Self.action(for: permission, status: status) {
        case .none:
            break
        case .grant:
            _ = await client.request(permission)
        case .openSettings:
            client.openSystemSettings(permission)
        }
        await refresh()
    }

    static func action(for permission: AppPermission, status: PermissionStatus) -> PermissionRowAction {
        switch status {
        case .granted:
            return .none
        case .denied:
            return .openSettings
        case .notDetermined:
            return permission == .pasteboard ? .openSettings : .grant
        case .unavailable:
            switch permission {
            case .automation, .pasteboard: return .openSettings
            default: return .none
            }
        }
    }

    static func statusText(for permission: AppPermission, status: PermissionStatus) -> String {
        switch status {
        case .granted:
            return "Allowed"
        case .denied:
            return "Not allowed"
        case .notDetermined:
            switch permission {
            case .pasteboard: return "Asks each time"
            case .accessibility: return "Not allowed yet"
            case .fullDiskAccess: return "Not checked (notifications from other apps are off)"
            default: return "Not asked yet"
            }
        case .unavailable:
            switch permission {
            case .automation(let target): return "Open \(target.displayName) to check"
            case .fullDiskAccess: return "Unknown"
            default: return "Unavailable"
            }
        }
    }

    static func featureText(for permission: AppPermission) -> String {
        switch permission {
        case .accessibility: return "Volume and brightness HUDs, media keys"
        case .fullDiskAccess: return "Notifications from other apps"
        case .camera: return "Mirror"
        case .calendar: return "Calendar and meeting countdown"
        case .automation(.music): return "Apple Music as music source"
        case .automation(.spotify): return "Spotify as music source"
        case .automation(.terminal), .automation(.iterm): return "Jump to a Claude Code session tab"
        case .pasteboard: return "Vitrin clipboard history"
        }
    }

    static func buttonTitle(for action: PermissionRowAction) -> String? {
        switch action {
        case .grant: return "Grant…"
        case .openSettings: return "Open System Settings"
        case .none: return nil
        }
    }

    static func symbol(for permission: AppPermission) -> String {
        switch permission {
        case .accessibility: return "accessibility"
        case .fullDiskAccess: return "externaldrive"
        case .camera: return "camera"
        case .calendar: return "calendar"
        case .automation(.music): return "music.note"
        case .automation(.spotify): return "waveform"
        case .automation: return "terminal"
        case .pasteboard: return "doc.on.clipboard"
        }
    }
}

struct PermissionsSettings: View {
    @StateObject private var model = PermissionsSettingsModel()

    var body: some View {
        Form {
            Section {
                ForEach(PermissionsSettingsModel.rows, id: \.self) { permission in
                    PermissionRow(
                        permission: permission,
                        status: model.statuses[permission],
                        perform: { Task { await model.perform(permission) } }
                    )
                }
            } footer: {
                Text("Nubrix reads these without asking. Each permission is asked only when you use its feature.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Permissions")
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }
}

private struct PermissionRow: View {
    let permission: AppPermission
    let status: PermissionStatus?
    let perform: () -> Void

    private var resolved: PermissionStatus { status ?? .unavailable }

    private var color: Color {
        switch resolved {
        case .granted: return .green
        case .notDetermined: return .orange
        case .denied: return .red
        case .unavailable: return .gray
        }
    }

    var body: some View {
        let action = PermissionsSettingsModel.action(for: permission, status: resolved)
        HStack(spacing: 12) {
            Image(systemName: PermissionsSettingsModel.symbol(for: permission))
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(permission.displayName)
                Text(PermissionsSettingsModel.featureText(for: permission))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if status != nil {
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(PermissionsSettingsModel.statusText(for: permission, status: resolved))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let title = PermissionsSettingsModel.buttonTitle(for: action) {
                    Button(title, action: perform)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
