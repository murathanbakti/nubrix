import Defaults
import SwiftUI

/// The features someone picks during onboarding. Starts from the current
/// settings, so it shows the defaults on a new Mac.
struct OnboardingChoices: Equatable {
    var music = Defaults[.mediaControlEnabled]
    var volumeAndBrightness = Defaults[.hudReplacement]
    var calendar = Defaults[.showCalendar]
    var shelf = Defaults[.nubrixShelf]
    var clipboard = Defaults[.vitrinEnabled]
    var deviceBatteries = Defaults[.deviceBatteryEnabled] || Defaults[.everydaySoundOutput] || Defaults[.everydayDrives]
        || Defaults[.everydayMicCamera] || Defaults[.everydayInternet] || Defaults[.everydayScreenShare]
    var appNotifications = Defaults[.systemNotificationsEnabled]
    var developerTools = Defaults[.claudeEnabled] || Defaults[.devEnabled] || Defaults[.githubEnabled]

    @MainActor
    func apply() {
        Defaults[.mediaControlEnabled] = music
        Defaults[.showCalendar] = calendar
        Defaults[.meetingCountdownEnabled] = calendar
        Defaults[.nubrixShelf] = shelf
        Defaults[.vitrinEnabled] = clipboard
        Defaults[.deviceBatteryEnabled] = deviceBatteries
        Defaults[.everydaySoundOutput] = deviceBatteries
        Defaults[.everydayDrives] = deviceBatteries
        Defaults[.everydayMicCamera] = deviceBatteries
        Defaults[.everydayInternet] = deviceBatteries
        Defaults[.everydayScreenShare] = deviceBatteries
        Defaults[.claudeEnabled] = developerTools
        Defaults[.devEnabled] = developerTools
        Defaults[.githubEnabled] = developerTools

        if volumeAndBrightness {
            AccessibilityGrantWatcher.turnOnHUDWhenAllowed()
        } else {
            Defaults[.hudReplacement] = false
        }
        if appNotifications {
            if !Defaults[.systemNotificationsEnabled] { FullDiskAccessGuide.begin(origin: .notch) }
        } else if Defaults[.systemNotificationsEnabled] {
            Defaults[.systemNotificationsEnabled] = false
            SystemNotificationStore.shared.settingChanged()
        }
        // firstLaunch is cleared right after this, so start on the next turn.
        DispatchQueue.main.async {
            DeviceBatteryStore.shared.start()
            EverydayAlertStore.shared.start()
        }
    }
}

/// Turns on the volume and brightness HUDs once Accessibility is allowed.
/// Allowing it happens in System Settings, so this keeps watching for a while
/// after onboarding closes.
@MainActor
enum AccessibilityGrantWatcher {
    private static var observer: NSObjectProtocol?
    private static var timeout: Task<Void, Never>?

    static func turnOnHUDWhenAllowed() {
        guard !Defaults[.hudReplacement] else { return }
        Task { @MainActor in
            if await XPCHelperClient.shared.isAccessibilityAuthorized() {
                Defaults[.hudReplacement] = true
                return
            }
            watch()
            _ = await Permissions.client.request(.accessibility)
        }
    }

    private static func watch() {
        stop()
        observer = NotificationCenter.default.addObserver(
            forName: .accessibilityAuthorizationChanged, object: nil, queue: .main
        ) { notification in
            guard notification.userInfo?["granted"] as? Bool == true else { return }
            MainActor.assumeIsolated {
                stop()
                Defaults[.hudReplacement] = true
            }
        }
        XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        timeout = Task { @MainActor in
            try? await Task.sleep(for: .seconds(15 * 60))
            guard !Task.isCancelled else { return }
            stop()
        }
    }

    private static func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timeout?.cancel()
        timeout = nil
        XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
    }
}

struct OnboardingFeaturesView: View {
    let onContinue: () -> Void
    @State private var choices = OnboardingChoices()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("What do you want in your notch?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                Text("You can change these any time in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 36)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 2) {
                    row("music.note", "Music", "See and control what is playing, in any app.", $choices.music)
                    row("calendar", "Calendar and meetings", "Upcoming events and a countdown before meetings.", $choices.calendar)
                    row("airpods", "Device and Mac alerts", "AirPods battery, drives, sound output and internet.", $choices.deviceBatteries)
                    row("tray.full", "File shelf", "Drop files on the notch to keep them close.", $choices.shelf)
                    row("doc.on.clipboard", "Clipboard history", "Find things you copied earlier.", $choices.clipboard)
                    row("speaker.wave.2", "Volume and brightness", "Shown in the notch instead of the middle of the screen. Asks for Accessibility.", $choices.volumeAndBrightness)
                    row("bell.badge", "Notifications from apps", "WhatsApp, Messages and other apps appear in the notch. Asks for Full Disk Access.", $choices.appNotifications)
                    row("chevron.left.forwardslash.chevron.right", "I write code", "Claude Code, GitHub and local server tabs.", $choices.developerTools)
                }
                .padding(.horizontal, 16)
            }

            VStack(spacing: 10) {
                Text("Everything stays on your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    choices.apply()
                    onContinue()
                } label: {
                    Text("Continue")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private func row(_ symbol: String, _ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.effectiveAccent)
                    .frame(width: 24, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}

#Preview {
    OnboardingFeaturesView(onContinue: {})
        .frame(width: 400, height: 600)
}
