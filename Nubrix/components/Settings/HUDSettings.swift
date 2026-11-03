import Defaults
import SwiftUI

struct HUDSettings: View {
    @Default(.inlineHUD) var inlineHUD
    @Default(.enableGradient) var enableGradient
    @Default(.optionKeyAction) var optionKeyAction
    @Default(.hudReplacement) var hudReplacement
    @Default(.showOpenNotchHUD) var showOpenNotchHUD
    @State private var accessibilityAuthorized = false
    @State private var requestedAccessibility = false

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .hudReplacement) {
                    Text("Replace system HUDs")
                }
                .disabled(!accessibilityAuthorized)
                if !accessibilityAuthorized {
                    HStack {
                        Label("Needs Accessibility", systemImage: "lock.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant…") {
                            requestedAccessibility = true
                            Task { _ = await Permissions.client.request(.accessibility) }
                        }
                    }
                }
            } footer: {
                SettingsFooter("Replaces the macOS volume, display brightness and keyboard brightness HUDs. Accessibility is used only for those keys; nothing is recorded or sent.")
            }

            Group {
                Section {
                    Picker("Option key behavior", selection: $optionKeyAction) {
                        ForEach(OptionKeyAction.allCases) { opt in
                            Text(opt.title).tag(opt)
                        }
                    }
                    Picker("Progress bar style", selection: $enableGradient) {
                        Text("Hierarchical")
                            .tag(false)
                        Text("Gradient")
                            .tag(true)
                    }
                    Defaults.Toggle(key: .systemEventIndicatorShadow) {
                        Text("Enable glowing effect")
                    }
                    Defaults.Toggle(key: .systemEventIndicatorUseAccent) {
                        Text("Tint progress bar with accent color")
                    }
                } header: {
                    Text("Style")
                }

                Section {
                    Defaults.Toggle(key: .showOpenNotchHUD) {
                        Text("Show HUD in open notch")
                    }
                    Defaults.Toggle(key: .showOpenNotchHUDPercentage) {
                        Text("Show percentage in open notch")
                    }
                    .disabled(!showOpenNotchHUD)
                } header: {
                    HStack {
                        Text("Open notch")
                        customBadge(text: "Beta")
                    }
                }

                Section {
                    Picker("HUD style", selection: $inlineHUD) {
                        Text("Default")
                            .tag(false)
                        Text("Inline")
                            .tag(true)
                    }
                    .onChange(of: inlineHUD) {
                        if inlineHUD {
                            withAnimation {
                                Defaults[.systemEventIndicatorShadow] = false
                                Defaults[.enableGradient] = false
                            }
                        }
                    }
                    Defaults.Toggle(key: .showClosedNotchHUDPercentage) {
                        Text("Show percentage in closed notch")
                    }
                } header: {
                    Text("Closed notch")
                }
            }
            .disabled(!hudReplacement)
        }
        .settingsPage(.huds)
        .task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
        .onAppear {
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onDisappear {
            XPCHelperClient.shared.stopMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowDidShow)) { _ in
            XPCHelperClient.shared.startMonitoringAccessibilityAuthorization()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accessibilityAuthorizationChanged)) { notification in
            if let granted = notification.userInfo?["granted"] as? Bool {
                accessibilityAuthorized = granted
                if granted && requestedAccessibility {
                    requestedAccessibility = false
                    hudReplacement = true
                }
            }
        }
    }
}

extension OptionKeyAction {
    var title: String {
        self == .none ? "No action" : rawValue
    }
}
