//
//  NotchHomeView.swift
//  Nubrix
//
//  Created by Hugo Persson on 2024-08-18.
//  Modified by Harsh Vardhan Goswami & Richard Kunkli & Mustafa Ramadan
//

import Combine
import Defaults
import SwiftUI

// MARK: - Music Player Components

struct MusicPlayerView: View {
    @EnvironmentObject var vm: NubrixViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        HStack {
            AlbumArtView(vm: vm, albumArtNamespace: albumArtNamespace).padding(.all, 5)
            MusicControlsView().compositingGroup()
        }
    }
}

struct AlbumArtView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var vm: NubrixViewModel
    let albumArtNamespace: Namespace.ID

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if Defaults[.lightingEffect] {
                albumArtBackground
            }
            albumArtButton
        }
    }

    private var albumArtBackground: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(x: 1.3, y: 1.4)
            .rotationEffect(.degrees(92))
            .blur(radius: 40)
            .opacity(musicManager.isPlaying ? 0.5 : 0)
    }

    private var albumArtButton: some View {
        ZStack {
            Button {
                musicManager.openMusicApp()
            } label: {
                ZStack(alignment:.bottomTrailing) {
                    albumArtImage
                    appIconOverlay
                }
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(musicManager.isPlaying ? 1 : 0.85)
            
            albumArtDarkOverlay
        }
    }

    private var albumArtDarkOverlay: some View {
        Rectangle()
            .aspectRatio(1, contentMode: .fit)
            .foregroundColor(Color.black)
            .opacity(musicManager.isPlaying ? 0 : 0.8)
            .blur(radius: 50)
    }
                

    private var albumArtImage: some View {
        Image(nsImage: musicManager.albumArt)
            .resizable()
            .aspectRatio(1, contentMode: .fit)
            .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Defaults[.cornerRadiusScaling]
                        ? MusicPlayerImageSizes.cornerRadiusInset.opened
                        : MusicPlayerImageSizes.cornerRadiusInset.closed)
            )
    }

    @ViewBuilder
    private var appIconOverlay: some View {
        if vm.notchState == .open && !musicManager.usingAppIconForArtwork {
            AppIcon(for: musicManager.bundleIdentifier ?? "com.apple.Music")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .offset(x: 10, y: 10)
                .transition(.scale.combined(with: .opacity))
                .zIndex(2)
        }
    }
}

struct MusicControlsView: View {
    @ObservedObject var musicManager = MusicManager.shared
        @EnvironmentObject var vm: NubrixViewModel
    @Default(.musicControlSlots) private var slotConfig
    @Default(.musicControlSlotLimit) private var slotLimit

    var body: some View {
        VStack(alignment: .leading) {
            songInfoAndSlider
            slotToolbar
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var songInfoAndSlider: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                songInfo(width: geo.size.width)
                musicSlider
            }
        }
        .padding(.top, 10)
        .padding(.leading, 5)
    }

    private func songInfo(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MarqueeText(
                $musicManager.songTitle, font: .headline, nsFont: .headline, textColor: .white,
                frameWidth: width)
            MarqueeText(
                $musicManager.artistName,
                font: .headline,
                nsFont: .headline,
                weight: .medium,
                textColor: Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor)
                        .ensureMinimumBrightness(factor: 0.6) : .gray,
                frameWidth: width
            )
            if Defaults[.enableLyrics] {
                LyricsLineView(width: width)
            }
        }
    }

    private var musicSlider: some View {
        MusicSliderView()
            .padding(.top, 5)
            .frame(height: 36)
    }

    private var slotToolbar: some View {
        let slots = activeSlots
        return HStack(spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.offset) { index, slot in
                slotView(for: slot)
                    .frame(alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeSlots: [MusicControlButton] {
        let sanitizedLimit = min(
            max(slotLimit, MusicControlButton.minSlotCount),
            MusicControlButton.maxSlotCount
        )
        let padded = slotConfig.padded(to: sanitizedLimit, filler: .none)
        let result = Array(padded.prefix(sanitizedLimit))
        return result
    }

    @ViewBuilder
    private func slotView(for slot: MusicControlButton) -> some View {
        switch slot {
        case .shuffle:
            HoverButton(icon: "shuffle", iconColor: musicManager.isShuffled ? .red : .primary, scale: .medium) {
                MusicManager.shared.toggleShuffle()
            }
        case .previous:
            HoverButton(icon: "backward.fill", scale: .medium) {
                MusicManager.shared.previousTrack()
            }
        case .playPause:
            HoverButton(icon: musicManager.isPlaying ? "pause.fill" : "play.fill", scale: .large) {
                MusicManager.shared.togglePlay()
            }
        case .next:
            HoverButton(icon: "forward.fill", scale: .medium) {
                MusicManager.shared.nextTrack()
            }
        case .repeatMode:
            HoverButton(icon: repeatIcon, iconColor: repeatIconColor, scale: .medium) {
                MusicManager.shared.toggleRepeat()
            }
        case .volume:
            VolumeControlView()
        case .favorite:
            FavoriteControlButton()
        case .goBackward:
            HoverButton(icon: "gobackward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: -15)
            }
        case .goForward:
            HoverButton(icon: "goforward.15", scale: .medium) {
                MusicManager.shared.skip(seconds: 15)
            }
        case .none:
            Color.clear.frame(height: 1)
        }
    }

    private var repeatIcon: String {
        switch musicManager.repeatMode {
        case .off:
            return "repeat"
        case .all:
            return "repeat"
        case .one:
            return "repeat.1"
        }
    }

    private var repeatIconColor: Color {
        switch musicManager.repeatMode {
        case .off:
            return .primary
        case .all, .one:
            return .red
        }
    }
}

struct FavoriteControlButton: View {
    @ObservedObject var musicManager = MusicManager.shared

    var body: some View {
        HoverButton(icon: iconName, iconColor: iconColor, scale: .medium) {
            MusicManager.shared.toggleFavoriteTrack()
        }
        .disabled(!musicManager.canFavoriteTrack)
        .opacity(musicManager.canFavoriteTrack ? 1 : 0.35)
    }

    private var iconName: String {
        musicManager.isFavoriteTrack ? "heart.fill" : "heart"
    }

    private var iconColor: Color {
        musicManager.isFavoriteTrack ? .red : .primary
    }
}

private extension Array where Element == MusicControlButton {
    func padded(to length: Int, filler: MusicControlButton) -> [MusicControlButton] {
        if count >= length { return self }
        return self + Array(repeating: filler, count: length - count)
    }
}

// MARK: - Volume Control View

struct VolumeControlView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var volumeSliderValue: Double = 0.5
    @State private var dragging: Bool = false
    @State private var showVolumeSlider: Bool = false
    @State private var lastVolumeUpdateTime: Date = Date.distantPast
    private let volumeUpdateThrottle: TimeInterval = 0.1
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
                if musicManager.volumeControlSupported {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        showVolumeSlider.toggle()
                    }
                }
            }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(musicManager.volumeControlSupported ? .white : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!musicManager.volumeControlSupported)
            .frame(width: 24)

            if showVolumeSlider && musicManager.volumeControlSupported {
                CustomSlider(
                    value: $volumeSliderValue,
                    range: 0.0...1.0,
                    color: .white,
                    dragging: $dragging,
                    lastDragged: .constant(Date.distantPast),
                    onValueChange: { newValue in
                        MusicManager.shared.setVolume(to: newValue)
                    },
                    onDragChange: { newValue in
                        let now = Date()
                        if now.timeIntervalSince(lastVolumeUpdateTime) > volumeUpdateThrottle {
                            MusicManager.shared.setVolume(to: newValue)
                            lastVolumeUpdateTime = now
                        }
                    }
                )
                .frame(width: 48, height: 8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .clipped()
        .onReceive(musicManager.$volume) { volume in
            if !dragging {
                volumeSliderValue = volume
            }
        }
        .onReceive(musicManager.$volumeControlSupported) { supported in
            if !supported {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVolumeSlider = false
                }
            }
        }
        .onChange(of: showVolumeSlider) { _, isShowing in
            if isShowing {
                // Sync volume from app when slider appears
                Task {
                    await MusicManager.shared.syncVolumeFromActiveApp()
                }
            }
        }
        .onDisappear {
            // volumeUpdateTask?.cancel() // No longer needed
        }
    }
    
    
    private var volumeIcon: String {
        if !musicManager.volumeControlSupported {
            return "speaker.slash"
        } else if volumeSliderValue == 0 {
            return "speaker.slash.fill"
        } else if volumeSliderValue < 0.33 {
            return "speaker.1.fill"
        } else if volumeSliderValue < 0.66 {
            return "speaker.2.fill"
        } else {
            return "speaker.3.fill"
        }
    }
}

// MARK: - Main View

struct NotchHomeView: View {
    @EnvironmentObject var vm: NubrixViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = NubrixCoordinator.shared
    @ObservedObject var meeting = MeetingWatcher.shared
    @ObservedObject var agents = AgentSessionStore.shared
    @ObservedObject var plan = ClaudePlanUsageStore.shared
    @Default(.homeShowClaudeUsage) private var showClaudeUsage
    @Default(.mediaControlEnabled) private var mediaEnabled
    @Default(.claudeEnabled) private var claudeEnabled
    let albumArtNamespace: Namespace.ID

    var body: some View {
        Group {
            if !coordinator.firstLaunch {
                mainContent
            }
        }
        // simplified: use a straightforward opacity transition
        .transition(.opacity)
        .onAppear { if vm.notchState == .open { plan.notchOpened() } }
        .onChange(of: vm.notchState) { _, state in
            if state == .open { plan.notchOpened() }
        }
    }

    private var showsClaudeCard: Bool {
        claudeEnabled && showClaudeUsage && !meeting.isCountdownActive && agents.usageSummary(now: Date()) != nil
    }

    private var mainContent: some View {
        ZStack(alignment: .top) {
            homeRow
        }
        .blur(radius: vm.notchState == .closed ? 30 : 0)
    }

    private var homeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            if mediaEnabled {
                MusicPlayerView(albumArtNamespace: albumArtNamespace)
            }

            if meeting.isCountdownActive {
                MeetingCardView()
                    .transition(.opacity)
            }

            if showsClaudeCard {
                ClaudeUsageCard(isActive: vm.notchState == .open) {
                    coordinator.currentView = .agents
                }
                .transition(.opacity)
            }
        }
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
    }
}

struct LyricsLineView: View {
    @ObservedObject var musicManager = MusicManager.shared
    let width: CGFloat
    @State private var line = ""
    @State private var rearmTask: Task<Void, Never>?

    private struct Key: Equatable {
        var timestamp: Date
        var elapsed: Double
        var isPlaying: Bool
        var rate: Double
        var duration: Double
        var lyricCount: Int
        var fetching: Bool
        var lyrics: String
    }

    private var key: Key {
        Key(
            timestamp: musicManager.timestampDate,
            elapsed: musicManager.elapsedTime,
            isPlaying: musicManager.isPlaying,
            rate: musicManager.playbackRate,
            duration: musicManager.songDuration,
            lyricCount: musicManager.syncedLyrics.count,
            fetching: musicManager.isFetchingLyrics,
            lyrics: musicManager.currentLyrics
        )
    }

    var body: some View {
        MarqueeText(
            .constant(line),
            font: .subheadline,
            nsFont: .subheadline,
            textColor: musicManager.isFetchingLyrics ? .gray.opacity(0.7) : .gray,
            frameWidth: width
        )
        .id(line)
        .transition(.opacity)
        .opacity(musicManager.isPlaying ? 1 : 0)
        .onChange(of: key, initial: true) { _, _ in rearm() }
        .onDisappear {
            rearmTask?.cancel()
            rearmTask = nil
        }
    }

    private func currentLine(at elapsed: Double) -> String {
        if musicManager.isFetchingLyrics { return "Loading lyrics…" }
        if !musicManager.syncedLyrics.isEmpty {
            return musicManager.lyricLine(at: elapsed)
        }
        let trimmed = musicManager.currentLyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No lyrics found" : trimmed.replacingOccurrences(of: "\n", with: " ")
    }

    private func rearm() {
        rearmTask?.cancel()
        rearmTask = nil
        let elapsed = musicManager.estimatedPlaybackPosition()
        let newLine = currentLine(at: elapsed)
        if newLine != line {
            withAnimation(.easeInOut(duration: 0.2)) { line = newLine }
        }
        guard musicManager.isPlaying, musicManager.playbackRate > 0,
              !musicManager.isFetchingLyrics,
              let next = musicManager.syncedLyrics.first(where: { $0.time > elapsed }) else { return }
        let delay = (next.time - elapsed) / musicManager.playbackRate + 0.02
        rearmTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            rearm()
        }
    }
}

struct MusicProgressState: Equatable {
    var duration: Double
    var elapsed: Double
    var timestamp: Date
    var rate: Double
    var isPlaying: Bool
    var pinned: Double?
}

final class MusicProgressLayerView: NSView {
    private let track = CALayer()
    private let fill = CALayer()
    private var applied: MusicProgressState?
    private var thick = false

    var tint: NSColor = .white {
        didSet {
            if tint != oldValue { updateColors() }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        track.masksToBounds = true
        fill.anchorPoint = CGPoint(x: 0, y: 0.5)
        track.addSublayer(fill)
        layer?.addSublayer(track)
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        updateGeometry(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    func setThick(_ value: Bool) {
        guard value != thick else { return }
        thick = value
        updateGeometry(animated: true)
    }

    func apply(_ state: MusicProgressState) {
        guard state != applied else { return }
        applied = state
        refresh()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            track.backgroundColor = NSColor.systemGray.withAlphaComponent(0.3).cgColor
            fill.backgroundColor = tint.cgColor
            CATransaction.commit()
        }
    }

    private func updateGeometry(animated: Bool) {
        let height: CGFloat = thick ? 9 : 5
        let width = bounds.width
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        track.frame = CGRect(x: 0, y: (bounds.height - height) / 2, width: width, height: height)
        track.cornerRadius = height / 2
        fill.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        fill.position = CGPoint(x: 0, y: height / 2)
        CATransaction.commit()
    }

    private func refresh() {
        fill.removeAnimation(forKey: "progress")
        guard let state = applied else { return }
        let duration = state.duration
        var fraction = 0.0
        if duration > 0 {
            var elapsed = state.elapsed
            if let pinned = state.pinned {
                elapsed = pinned
            } else if state.isPlaying {
                elapsed += Date().timeIntervalSince(state.timestamp) * state.rate
            }
            fraction = min(max(elapsed, 0), duration) / duration
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.transform = CATransform3DMakeScale(CGFloat(fraction), 1, 1)
        CATransaction.commit()

        guard window != nil, duration > 0, state.pinned == nil, state.isPlaying,
              state.rate > 0, fraction < 1 else { return }
        let progress = CABasicAnimation(keyPath: "transform.scale.x")
        progress.fromValue = fraction
        progress.toValue = 1.0
        progress.duration = duration * (1 - fraction) / state.rate
        progress.fillMode = .forwards
        progress.isRemovedOnCompletion = false
        progress.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 20, preferred: 15)
        fill.add(progress, forKey: "progress")
    }
}

struct MusicProgressTrack: NSViewRepresentable {
    let state: MusicProgressState
    let color: NSColor
    let thick: Bool

    func makeNSView(context: Context) -> MusicProgressLayerView {
        MusicProgressLayerView()
    }

    func updateNSView(_ nsView: MusicProgressLayerView, context: Context) {
        nsView.tint = color
        nsView.setThick(thick)
        nsView.apply(state)
    }
}

struct MusicSliderView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @State private var pinned: Double?
    @State private var dragging = false
    @State private var releaseTask: Task<Void, Never>?

    private var tint: Color {
        Defaults[.sliderColor] == SliderColorEnum.albumArt
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.8)
            : Defaults[.sliderColor] == SliderColorEnum.accent ? .effectiveAccent : .white
    }

    private var state: MusicProgressState {
        MusicProgressState(
            duration: musicManager.songDuration,
            elapsed: musicManager.elapsedTime,
            timestamp: musicManager.timestampDate,
            rate: musicManager.playbackRate,
            isPlaying: musicManager.isPlaying,
            pinned: pinned
        )
    }

    var body: some View {
        VStack {
            GeometryReader { geometry in
                MusicProgressTrack(state: state, color: NSColor(tint), thick: dragging)
                    .frame(width: geometry.size.width, height: 10)
                    .overlay(
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(dragGesture(width: geometry.size.width))
                    )
            }
            .frame(height: 10, alignment: .center)

            HStack {
                elapsedLabel
                Spacer()
                Text(timeString(from: musicManager.songDuration))
            }
            .fontWeight(.medium)
            .foregroundColor(
                Defaults[.playerColorTinting]
                    ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray
            )
            .font(.caption)
        }
        .onDisappear {
            releaseTask?.cancel()
            releaseTask = nil
            pinned = nil
            dragging = false
        }
    }

    @ViewBuilder
    private var elapsedLabel: some View {
        if let pinned {
            Text(timeString(from: pinned))
        } else if musicManager.isPlaying {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timeString(from: musicManager.estimatedPlaybackPosition(at: context.date)))
            }
        } else {
            Text(timeString(from: musicManager.estimatedPlaybackPosition()))
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let duration = musicManager.songDuration
                guard duration > 0, width > 0 else { return }
                releaseTask?.cancel()
                releaseTask = nil
                dragging = true
                let newValue = Double(gesture.location.x / width) * duration
                pinned = min(max(newValue, 0), duration)
            }
            .onEnded { _ in
                dragging = false
                if let value = pinned {
                    MusicManager.shared.seek(to: value)
                }
                releaseTask?.cancel()
                releaseTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    guard !Task.isCancelled else { return }
                    pinned = nil
                }
            }
    }

    func timeString(from seconds: Double) -> String {
        let totalMinutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        } else {
            return String(format: "%d:%02d", minutes, remainingSeconds)
        }
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var color: Color = .white
    @Binding var dragging: Bool
    @Binding var lastDragged: Date
    var onValueChange: ((Double) -> Void)?
    var onDragChange: ((Double) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = CGFloat(dragging ? 9 : 5)
            let rangeSpan = range.upperBound - range.lowerBound

            let progress = rangeSpan == .zero ? 0 : (value - range.lowerBound) / rangeSpan
            let filledTrackWidth = min(max(progress, 0), 1) * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)

                Rectangle()
                    .fill(color)
                    .frame(width: filledTrackWidth, height: height)
            }
            .cornerRadius(height / 2)
            .frame(height: 10)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation {
                            dragging = true
                        }
                        let newValue = range.lowerBound + Double(gesture.location.x / width) * rangeSpan
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                        onDragChange?(value)
                    }
                    .onEnded { _ in
                        onValueChange?(value)
                        dragging = false
                        lastDragged = Date()
                    }
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: dragging)
        }
    }
}
