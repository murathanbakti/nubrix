import Defaults
import SwiftUI

struct MediaSettings: View {
    @Default(.waitInterval) var waitInterval
    @Default(.mediaController) var mediaController
    @ObservedObject var coordinator = NubrixCoordinator.shared
    @Default(.hideNotchOption) var hideNotchOption
    @Default(.enableSneakPeek) private var enableSneakPeek
    @Default(.sneakPeekStyles) var sneakPeekStyles
    @Default(.mediaControlEnabled) var mediaEnabled

    private static let pearDesktopURL = URL(string: "https://github.com/pear-devs/pear-desktop")!

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .mediaControlEnabled) {
                    Text("Enable media control")
                }
            } footer: {
                SettingsFooter("Shows what is playing and controls Apple Music, Spotify, YouTube Music or the system player. When off, Nubrix does not read playback or send commands to music apps.")
            }

            Group {
                sourceSection
                playbackSection
                controlsSection
            }
            .disabled(!mediaEnabled)
        }
        .settingsPage(.media)
    }

    private var sourceSection: some View {
        Section {
            Picker("Music source", selection: $mediaController) {
                ForEach(availableMediaControllers) { controller in
                    Text(controller.rawValue).tag(controller)
                }
            }
            .onChange(of: mediaController) { _, _ in
                NotificationCenter.default.post(
                    name: Notification.Name.mediaControllerChanged,
                    object: nil
                )
            }
        } header: {
            Text("Source")
        } footer: {
            if MusicManager.shared.isNowPlayingDeprecated {
                SettingsFooter("YouTube Music needs the Pear Desktop app.", link: ("Get Pear Desktop", Self.pearDesktopURL))
            } else {
                SettingsFooter("Now Playing works with all media apps.")
            }
        }
    }

    private var playbackSection: some View {
        Section {
            Toggle(
                "Show music live activity",
                isOn: $coordinator.musicLiveActivityEnabled.animation()
            )
            Toggle("Show sneak peek on playback changes", isOn: $enableSneakPeek)
            Picker("Sneak peek style", selection: $sneakPeekStyles) {
                ForEach(SneakPeekStyle.allCases) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            Stepper(value: $waitInterval, in: 0...10, step: 1) {
                HStack {
                    Text("Media inactivity timeout")
                    Spacer()
                    Text("\(waitInterval, specifier: "%.0f") seconds")
                        .foregroundStyle(.secondary)
                }
            }
            Picker(
                selection: $hideNotchOption,
                label:
                    HStack {
                        Text("Full screen behavior")
                        customBadge(text: "Beta")
                    }
            ) {
                Text("Hide for all apps").tag(HideNotchOption.always)
                Text("Hide for media app only").tag(HideNotchOption.nowPlayingOnly)
                Text("Never hide").tag(HideNotchOption.never)
            }
        } header: {
            Text("Playback")
        }
    }

    private var controlsSection: some View {
        Section {
            MusicSlotConfigurationView()
            Defaults.Toggle(key: .enableLyrics) {
                HStack {
                    Text("Show lyrics below artist name")
                    customBadge(text: "Beta")
                }
            }
        } header: {
            Text("Controls")
        } footer: {
            SettingsFooter("Choose which controls appear in the music player. Volume expands when active.")
        }
    }

    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
}
