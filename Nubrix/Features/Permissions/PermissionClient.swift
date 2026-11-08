import AppKit
import ApplicationServices
import AVFoundation
import CoreLocation
import EventKit
import Foundation

enum AutomationTarget: String, CaseIterable {
    case music = "com.apple.Music"
    case spotify = "com.spotify.client"
    case terminal = "com.apple.Terminal"
    case iterm = "com.googlecode.iterm2"
    case ghostty = "com.mitchellh.ghostty"

    var displayName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .terminal: return "Terminal"
        case .iterm: return "iTerm"
        case .ghostty: return "Ghostty"
        }
    }
}

enum AppPermission: Hashable {
    case accessibility
    case fullDiskAccess
    case camera
    case calendar
    case location
    case automation(AutomationTarget)
    case pasteboard

    var displayName: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .fullDiskAccess: return "Full Disk Access"
        case .camera: return "Camera"
        case .calendar: return "Calendar"
        case .location: return "Location"
        case .automation(let target): return "Automation for \(target.displayName)"
        case .pasteboard: return "Paste from Other Apps"
        }
    }
}

enum PermissionStatus: Equatable {
    case granted
    case denied
    case notDetermined
    case unavailable
}

@MainActor
protocol PermissionClient: AnyObject {
    func status(_ permission: AppPermission) async -> PermissionStatus
    func request(_ permission: AppPermission) async -> PermissionStatus
    func openSystemSettings(_ permission: AppPermission)
}

@MainActor
enum Permissions {
    static var client: any PermissionClient = SystemPermissionClient()
}

@MainActor
final class SystemPermissionClient: PermissionClient {
    func status(_ permission: AppPermission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            return await XPCHelperClient.shared.isAccessibilityAuthorized() ? .granted : .notDetermined
        case .fullDiskAccess:
            return Self.map(await SystemNotificationStore.shared.checkNow())
        case .camera:
            return Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .calendar:
            return Self.map(EKEventStore.authorizationStatus(for: .event))
        case .location:
            return Self.map(CLLocationManager().authorizationStatus)
        case .automation(let target):
            return await Self.automationStatus(target, ask: false)
        case .pasteboard:
            return Self.pasteboardStatus()
        }
    }

    func request(_ permission: AppPermission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            return await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true) ? .granted : .notDetermined
        case .fullDiskAccess:
            FullDiskAccessGuide.begin(origin: .permissions)
            return await status(.fullDiskAccess)
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
            return Self.map(AVCaptureDevice.authorizationStatus(for: .video))
        case .calendar:
            _ = try? await SharedEventStore.shared.store.requestFullAccessToEvents()
            return Self.map(EKEventStore.authorizationStatus(for: .event))
        case .location:
            return Self.map(await LocationAuthorizer.shared.request())
        case .automation(let target):
            guard Self.isRunning(target) else {
                openSystemSettings(permission)
                return .unavailable
            }
            return await Self.automationStatus(target, ask: true)
        case .pasteboard:
            openSystemSettings(permission)
            return Self.pasteboardStatus()
        }
    }

    func openSystemSettings(_ permission: AppPermission) {
        let pane: String
        switch permission {
        case .accessibility: pane = "Privacy_Accessibility"
        case .fullDiskAccess: pane = "Privacy_AllFiles"
        case .camera: pane = "Privacy_Camera"
        case .calendar: pane = "Privacy_Calendars"
        case .location: pane = "Privacy_LocationServices"
        case .automation: pane = "Privacy_Automation"
        case .pasteboard: pane = "Privacy_Pasteboard"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func map(_ status: SystemNotificationStatus) -> PermissionStatus {
        switch status {
        case .ready: return .granted
        case .noAccess: return .denied
        case .off: return .notDetermined
        case .waiting, .notFound, .unsupported, .failed: return .unavailable
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted, .writeOnly: return .denied
        @unknown default: return .denied
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    private static func pasteboardStatus() -> PermissionStatus {
        if #available(macOS 15.4, *) {
            switch NSPasteboard.general.accessBehavior {
            case .alwaysAllow, .default: return .granted
            case .ask: return .notDetermined
            case .alwaysDeny: return .denied
            @unknown default: return .notDetermined
            }
        }
        return .granted
    }

    private static func isRunning(_ target: AutomationTarget) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: target.rawValue).isEmpty
    }

    private static func automationStatus(_ target: AutomationTarget, ask: Bool) async -> PermissionStatus {
        guard isRunning(target) else { return .unavailable }
        let bundleID = target.rawValue
        let code = await Task.detached(priority: .userInitiated) { () -> OSStatus in
            let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            return AEDeterminePermissionToAutomateTarget(
                descriptor.aeDesc,
                AEEventClass(typeWildCard),
                AEEventID(typeWildCard),
                ask
            )
        }.value
        switch code {
        case noErr: return .granted
        case -1743: return .denied
        case -1744: return .notDetermined
        default: return .unavailable
        }
    }
}

/// Asks for Location (When In Use). macOS treats Wi-Fi network names as location data, so the
/// Controls tab needs it for "Show network names". Only called when the user taps that row or Grant.
@MainActor
final class LocationAuthorizer: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuthorizer()
    private var manager: CLLocationManager?

    func request() async -> CLAuthorizationStatus {
        let manager = CLLocationManager()
        manager.delegate = self
        self.manager = manager
        guard manager.authorizationStatus == .notDetermined else { return manager.authorizationStatus }
        // A menu bar app has no active window; the prompt needs the app in front.
        NSApp.activate(ignoringOtherApps: true)
        manager.requestWhenInUseAuthorization()
        // The answer comes back through the delegate; the status is enough to read here.
        for _ in 0..<240 {
            try? await Task.sleep(for: .milliseconds(250))
            if manager.authorizationStatus != .notDetermined { break }
        }
        return manager.authorizationStatus
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
}
