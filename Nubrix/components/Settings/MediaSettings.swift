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
                    Text(Self.pickerTitle(for: controller)).tag(controller)
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
            sourceFooter
        }
    }

    @ViewBuilder
    private var sourceFooter: some View {
        let nowPlayingAvailable = !MusicManager.shared.isNowPlayingDeprecated
        switch mediaController {
        case .nowPlaying:
            SettingsFooter("Follows whatever is playing on your Mac, including Chrome, Safari and other browsers.")
        case .youtubeMusic:
            SettingsFooter("YouTube Music needs the Pear Desktop app.", link: ("Get Pear Desktop", Self.pearDesktopURL))
        case .appleMusic, .spotify:
            if nowPlayingAvailable {
                SettingsFooter("Only follows \(mediaController.rawValue). To control music playing in a browser or another app, choose Any app.")
            } else {
                SettingsFooter("Only follows \(mediaController.rawValue). Following any app, including browsers, is not available on this version of macOS.")
            }
        }
    }

    private static func pickerTitle(for controller: MediaControllerType) -> String {
        controller == .nowPlaying ? "Any app (Now Playing)" : controller.rawValue
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
