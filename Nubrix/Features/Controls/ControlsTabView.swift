import CoreAudio
import Defaults
import SwiftUI

// MARK: - Style

private enum ControlsStyle {
    static let ink = Color(white: 0.11)
    static func ink(_ palette: ThemePalette) -> Color { palette.theme.resolvedForeground == .light ? ink : Color(white: 0.96) }
    static func hairline(_ palette: ThemePalette) -> Color { palette.foreground.opacity(0.08) }
    static let sliderSpring = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let hoverFade = Animation.easeOut(duration: 0.12)
}

// MARK: - Capsule slider

/// Control Center style slider: a capsule with the symbol inside on the left and the value on the right.
/// Dragging is relative to where it started; a plain click jumps to that point.
private struct ControlsCapsuleSlider: View {
    @Environment(\.nubrixPalette) private var palette
    let symbol: String
    let value: Double
    let valueText: String
    var enabled = true
    var height = ControlsSliderMetrics.height
    var symbolAction: (() -> Void)?
    let onChange: (Double) -> Void

    @State private var local: Double?
    @State private var dragStart: Double?
    @State private var releaseToken = 0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let shown = max(0, min(1, local ?? value))
            let fill = ControlsSliderMetrics.fillWidth(value: shown, width: width, height: height)
            let symbolDark = ControlsSliderMetrics.symbolOnFill(value: shown, width: width, height: height)
            let valueDark = ControlsSliderMetrics.valueOnFill(value: shown, width: width, height: height)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.foreground.opacity(0.10))
                Capsule()
                    .fill(palette.foreground.opacity(0.92))
                    .frame(width: fill)
                    .animation(ControlsStyle.sliderSpring, value: fill)
                symbolView(dark: symbolDark)
                Text(valueText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(valueDark ? ControlsStyle.ink(palette) : palette.foreground.opacity(0.55))
                    .padding(.trailing, 11)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .allowsHitTesting(false)
                    .animation(ControlsStyle.hoverFade, value: valueDark)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
            .gesture(drag(width: width))
        }
        .frame(height: height)
        .opacity(enabled ? 1 : 0.4)
        .allowsHitTesting(enabled)
    }

    @ViewBuilder
    private func symbolView(dark: Bool) -> some View {
        let image = Image(systemName: symbol)
            .font(.system(size: 14))
            .foregroundStyle(dark ? ControlsStyle.ink(palette) : palette.foreground.opacity(0.8))
            .frame(width: 30, height: height)
            .contentTransition(.symbolEffect(.replace))
            .animation(ControlsStyle.hoverFade, value: dark)
        if let symbolAction {
            Button(action: symbolAction) { image.contentShape(Rectangle()) }
                .buttonStyle(.plain)
        } else {
            image.allowsHitTesting(false)
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                releaseToken += 1
                if dragStart == nil { dragStart = max(0, min(1, local ?? value)) }
                // A real drag moves relative to the start; a click is settled when it ends.
                guard abs(drag.translation.width) > 3, let start = dragStart else { return }
                let v = max(0, min(1, start + Double(drag.translation.width / max(width, 1))))
                local = v
                onChange(v)
            }
            .onEnded { drag in
                let moved = abs(drag.translation.width) > 3
                let v: Double
                if moved, let start = dragStart {
                    v = max(0, min(1, start + Double(drag.translation.width / max(width, 1))))
                } else {
                    v = max(0, min(1, Double(drag.location.x / max(width, 1))))
                }
                dragStart = nil
                local = v
                onChange(v)
                let token = releaseToken
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if token == releaseToken { local = nil }
                }
            }
    }
}

// MARK: - Left column

private func percentText(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

/// The Bluetooth rune, drawn by hand because SF Symbols has no Bluetooth symbol on macOS 14.
private struct ControlsBluetoothGlyph: View {
    var color: Color = .white
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0.12, y: 0.30))
            p.addLine(to: CGPoint(x: 0.88, y: 0.72))
            p.addLine(to: CGPoint(x: 0.50, y: 1.0))
            p.addLine(to: CGPoint(x: 0.50, y: 0.0))
            p.addLine(to: CGPoint(x: 0.88, y: 0.28))
            p.addLine(to: CGPoint(x: 0.12, y: 0.70))
        }
        .applying(CGAffineTransform(scaleX: 10, y: 18))
        .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        .frame(width: 10, height: 18)
    }
}

private struct ControlsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// One of the five round quick toggles: a 40 pt circle with a label under it.
private struct ControlsQuickToggle: View {
    @Environment(\.nubrixPalette) private var palette
    let state: ControlsToggleState
    var busy = false
    var enabled = true
    let action: () -> Void

    private var fill: Color {
        switch state.fill {
        case .accent: Color.effectiveAccent
        case .neutral: palette.foreground.opacity(0.12)
        case .red: Color.red.opacity(0.9)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle().fill(fill)
                    if busy {
                        ControlsSpinner()
                    } else if state.symbol == ControlsToggles.bluetoothGlyph {
                        ControlsBluetoothGlyph(color: state.fill == .neutral ? palette.foreground : .white)
                    } else {
                        Image(systemName: state.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(state.fill == .neutral ? palette.foreground : Color.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 40, height: 40)
                .animation(ControlsStyle.hoverFade, value: state.fill)
                Text(state.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.foreground.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(width: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(ControlsPressStyle())
        .disabled(busy || !enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(state.help)
        .accessibilityLabel(state.label)
    }
}

private struct ControlsLevels: View {
    @Environment(\.nubrixPalette) private var palette
    @ObservedObject var store: ControlsStore
    @Binding var tab: ControlsListTab
    @ObservedObject private var volume = VolumeManager.shared
    @ObservedObject private var brightness = BrightnessManager.shared
    @ObservedObject private var backlight = KeyboardBacklightManager.shared
    @ObservedObject private var share = ScreenShareMonitor.shared
    @Default(.hideFromScreenRecording) private var notchHidden

    private func select(_ item: ControlsListTab) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { tab = item }
    }

    private var shared: Bool { share.isShared }
    private var sliderHeight: CGFloat { shared ? ControlsSliderMetrics.compactHeight : ControlsSliderMetrics.height }

    var body: some View {
        VStack(alignment: .leading, spacing: shared ? 12 : 14) {
            toggles
            VStack(spacing: shared ? 6 : 8) {
                ControlsCapsuleSlider(
                    symbol: ControlsSliderMetrics.speakerSymbol(level: Double(volume.rawVolume), muted: volume.isMuted),
                    value: Double(volume.rawVolume),
                    valueText: volume.isMuted ? "Muted" : percentText(Double(volume.rawVolume)),
                    height: sliderHeight,
                    symbolAction: { volume.toggleMuteQuietly() }
                ) { volume.setAbsolute(Float($0)) }
                ControlsCapsuleSlider(
                    symbol: "sun.max.fill",
                    value: Double(brightness.rawBrightness),
                    valueText: brightness.isAvailable ? percentText(Double(brightness.rawBrightness)) : "Not available",
                    enabled: brightness.isAvailable,
                    height: sliderHeight
                ) { brightness.setAbsolute(value: Float($0)) }
                ControlsCapsuleSlider(
                    symbol: "light.max",
                    value: Double(backlight.rawBrightness),
                    valueText: !backlight.isAvailable ? "Not available" : (backlight.rawBrightness <= 0.005 ? "Off" : percentText(Double(backlight.rawBrightness))),
                    enabled: backlight.isAvailable,
                    height: sliderHeight
                ) { backlight.setAbsolute(value: Float($0)) }
            }
            if shared {
                sharingBanner
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: shared)
    }

    /// Orange strip under the sliders while someone else can see the screen.
    private var sharingBanner: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.orange).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 0) {
                Text("Screen is being shared")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(red: 1, green: 0.70, blue: 0.25))
                    .lineLimit(1)
                Text(share.state.detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(palette.foreground.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button { notchHidden.toggle() } label: {
                Text(notchHidden ? "Show notch" : "Hide notch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(palette.foreground.opacity(0.14)))
                    .contentShape(Capsule())
            }
            .buttonStyle(ControlsPressStyle())
            .help(notchHidden ? "Show the notch to people who see your screen" : "Hide the notch from people who see your screen")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 32)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.orange.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
        )
    }

    private var toggles: some View {
        HStack(spacing: 0) {
            ControlsQuickToggle(
                state: ControlsToggles.wifi(available: store.wifi.available, powered: store.wifi.powered),
                busy: store.wifiBusy == "",
                enabled: store.wifi.available
            ) {
                if store.wifi.available { store.setWiFiPower(!store.wifi.powered) }
                select(.wifi)
            }
            Spacer(minLength: 0)
            ControlsQuickToggle(
                state: ControlsToggles.bluetooth(on: store.bluetoothOn, switchable: store.bluetoothSwitchable),
                busy: store.bluetoothPowerBusy
            ) {
                store.toggleBluetoothPower()
                select(.bluetooth)
            }
            Spacer(minLength: 0)
            ControlsQuickToggle(state: ControlsToggles.sound(muted: volume.isMuted)) {
                volume.toggleMuteQuietly()
            }
            Spacer(minLength: 0)
            ControlsQuickToggle(
                state: ControlsToggles.mic(muted: MicMute.isMuted(store.inputVolume), settable: store.inputVolume != nil),
                enabled: store.inputVolume != nil
            ) {
                store.toggleMicMute()
            }
            Spacer(minLength: 0)
            Spacer(minLength: 0)
            ControlsQuickToggle(state: ControlsMirroring.toggle(mirroringTo: share.mirroringTo)) {
                ControlsMirroring.openSettings()
            }
        }
    }
}

// MARK: - Segmented control

private struct ControlsSegmented: View {
    @Environment(\.nubrixPalette) private var palette
    @Binding var selection: ControlsListTab
    let tabs: [ControlsListTab]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { item in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { selection = item }
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == item ? palette.foreground : palette.foreground.opacity(0.5))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            if selection == item {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(palette.foreground.opacity(0.14))
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.foreground.opacity(0.06)))
    }
}

// MARK: - Rows

/// "L 83%  R 83%  Case 41%": letters dim, numbers brighter, orange or red only when low.
private struct ControlsBatteryText: View {
    @Environment(\.nubrixPalette) private var palette
    let parts: [ControlsBatteryPart]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                HStack(spacing: 3) {
                    if let label = part.label {
                        Text(label).foregroundStyle(palette.foreground.opacity(0.4))
                    }
                    Text("\(part.level)%")
                        .foregroundStyle(ControlsSliderMetrics.isLowBattery(part.level) ? batteryRingTint(part.level) : palette.foreground.opacity(0.7))
                }
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            }
        }
    }
}

/// One 38 high row: circle with a symbol, name, a state line, and trailing content.
/// With an `action` the whole row is the button and fades in a hover fill.
private struct ControlsRow<Trailing: View>: View {
    @Environment(\.nubrixPalette) private var palette
    let symbol: String
    let name: String
    var subtitle: String?
    /// Accent circle: the selected output or input, or a connected Bluetooth device.
    var highlighted = false
    var circleFilled = true
    var nameOpacity = 1.0
    var action: (() -> Void)?
    @ViewBuilder var trailing: (_ hovering: Bool) -> Trailing

    @State private var hovering = false

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(highlighted ? Color.effectiveAccent : (circleFilled ? palette.foreground.opacity(0.10) : .clear))
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(highlighted ? Color.white : palette.foreground.opacity(circleFilled ? 0.85 : 0.5))
            }
            .frame(width: 28, height: 28)
            .animation(ControlsStyle.hoverFade, value: highlighted)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.foreground.opacity(nameOpacity))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.foreground.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing(hovering)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.foreground.opacity(hovering && action != nil ? 0.06 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .animation(ControlsStyle.hoverFade, value: hovering)
    }
}

private struct ControlsHint: View {
    @Environment(\.nubrixPalette) private var palette
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(palette.foreground.opacity(0.6))
            .lineLimit(1)
            .fixedSize()
            .transition(.opacity)
    }
}

/// Four bars like the menu bar Wi-Fi symbol; the ones above `bars` are dim.
private struct ControlsSignalBars: View {
    @Environment(\.nubrixPalette) private var palette
    let bars: Int
    private static let heights: [CGFloat] = [4, 6, 9, 11]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(palette.foreground.opacity(index < bars ? 0.8 : 0.2))
                    .frame(width: 3, height: Self.heights[index])
            }
        }
        .frame(height: 11)
        .accessibilityLabel("Signal \(bars) of 4")
    }
}

private struct ControlsSpinner: View {
    var body: some View {
        ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 16, height: 16)
    }
}

// MARK: - List

private struct ControlsList: View {
    @Environment(\.nubrixPalette) private var palette
    @ObservedObject var store: ControlsStore
    @Binding var tab: ControlsListTab

    private static let sizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 1) {
                switch tab {
                case .wifi: wifiRows
                case .output: audioRows(store.outputs, current: store.currentOutput, input: false)
                case .input: audioRows(store.inputs, current: store.currentInput, input: true)
                case .bluetooth: bluetoothRows
                case .drives: driveRows
                }
            }
            .id(tab)
            .transition(.opacity)
        }
    }

    // MARK: Wi-Fi

    @ViewBuilder
    private var wifiRows: some View {
        let wifi = store.wifi
        let namesHidden = store.locationStatus != .granted
        if let message = store.wifiMessage {
            Text(message)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.foreground.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
                .padding(.bottom, 2)
        }
        if !wifi.available {
            note("No Wi-Fi on this Mac")
        } else if !wifi.powered {
            note("Wi-Fi is off")
        } else {
            currentNetworkRow(wifi, namesHidden: namesHidden)
            if namesHidden {
                ControlsRow(
                    symbol: "location.fill",
                    name: "Show network names",
                    subtitle: store.locationStatus == .denied ? "Opens Location Services" : "Needs Location access",
                    action: { store.showNetworkNames() }
                ) { hovering in
                    if hovering { ControlsHint(text: store.locationStatus == .denied ? "Open" : "Allow") }
                }
            } else if !wifi.networks.isEmpty {
                Text("Other networks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.foreground.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                ForEach(wifi.networks) { network in
                    networkRow(network)
                }
            }
        }
        ControlsRow(
            symbol: "gearshape",
            name: "Wi-Fi Settings…",
            circleFilled: false,
            nameOpacity: 0.5,
            action: { store.openWiFiSettings() }
        ) { _ in EmptyView() }
    }

    @ViewBuilder
    private func currentNetworkRow(_ wifi: WiFiState, namesHidden: Bool) -> some View {
        if wifi.connected {
            let subtitle = wifi.ssid == nil || namesHidden
                ? wifi.ip
                : (wifi.ip.map { "Connected · \($0)" } ?? "Connected")
            ControlsRow(
                symbol: "wifi",
                name: wifi.ssid.flatMap { namesHidden ? nil : $0 } ?? "Connected",
                subtitle: subtitle,
                highlighted: true
            ) { _ in
                if wifi.rssi != 0 { ControlsSignalBars(bars: WiFiMetrics.bars(rssi: wifi.rssi)) }
            }
        } else {
            ControlsRow(symbol: "wifi.slash", name: "Not connected", nameOpacity: 0.7) { _ in EmptyView() }
        }
    }

    private func networkRow(_ network: WiFiNetwork) -> some View {
        let joining = store.wifiBusy == network.ssid
        return ControlsRow(
            symbol: "wifi",
            name: network.ssid,
            subtitle: joining ? "Joining…" : WiFiMetrics.securityText(network),
            action: joining ? nil : { store.join(network) }
        ) { hovering in
            if joining {
                ControlsSpinner()
            } else {
                HStack(spacing: 8) {
                    if hovering { ControlsHint(text: "Join") }
                    ControlsSignalBars(bars: WiFiMetrics.bars(rssi: network.rssi))
                }
            }
        }
    }

    // MARK: Output and input

    @ViewBuilder
    private func audioRows(_ devices: [AudioDeviceInfo], current: AudioObjectID?, input: Bool) -> some View {
        if input {
            ControlsCapsuleSlider(
                symbol: MicMute.isMuted(store.inputVolume) ? "mic.slash.fill" : "mic.fill",
                value: Double(store.inputVolume ?? 0),
                valueText: store.inputVolume == nil ? "Fixed" : (MicMute.isMuted(store.inputVolume) ? "Muted" : percentText(Double(store.inputVolume ?? 0))),
                enabled: store.inputVolume != nil
            ) { store.setInputVolume(Float($0)) }
            .padding(.bottom, 4)
        }
        if devices.isEmpty {
            note(input ? "No input devices" : "No output devices")
        } else {
            ForEach(devices) { device in
                let parts = ControlsBattery.match(uid: device.uid, name: device.name, in: store.bluetooth)?.battery ?? []
                ControlsRow(
                    symbol: device.symbol,
                    name: device.name,
                    subtitle: device.kind,
                    highlighted: device.id == current,
                    action: { store.select(device, input: input) }
                ) { _ in
                    if !parts.isEmpty { ControlsBatteryText(parts: parts) }
                }
            }
        }
    }

    // MARK: Bluetooth

    @ViewBuilder
    private var bluetoothRows: some View {
        if !store.bluetoothOn {
            ControlsRow(
                symbol: "dot.radiowaves.left.and.right",
                name: "Bluetooth is off",
                subtitle: store.bluetoothSwitchable ? "Turn it on to see your devices" : "Turn it on in Bluetooth settings",
                action: store.bluetoothPowerBusy ? nil : { store.toggleBluetoothPower() }
            ) { _ in
                if store.bluetoothPowerBusy {
                    ControlsSpinner()
                } else {
                    ControlsHint(text: store.bluetoothSwitchable ? "Turn On" : "Open")
                }
            }
        } else if store.bluetooth.isEmpty {
            note("No Bluetooth devices")
        } else {
            ForEach(store.bluetooth) { device in
                bluetoothRow(device)
            }
        }
        ControlsRow(
            symbol: "gearshape",
            name: "Bluetooth Settings…",
            circleFilled: false,
            nameOpacity: 0.5,
            action: { store.openBluetoothSettings() }
        ) { _ in EmptyView() }
    }

    private func bluetoothRow(_ device: ControlsBluetoothDevice) -> some View {
        let busy = store.busy.contains(device.id)
        let subtitle: String
        if busy {
            subtitle = device.connected ? "Disconnecting…" : "Connecting…"
        } else {
            subtitle = device.connected ? "Connected" : "Not connected"
        }
        let parts = device.connected && !busy ? device.battery : []
        return ControlsRow(
            symbol: device.symbol,
            name: device.name,
            subtitle: subtitle,
            highlighted: device.connected && !busy,
            action: busy ? nil : { store.toggle(device) }
        ) { hovering in
            if busy {
                ControlsSpinner()
            } else if hovering {
                ControlsHint(text: device.connected ? "Disconnect" : "Connect")
            } else if !parts.isEmpty {
                ControlsBatteryText(parts: parts).transition(.opacity)
            }
        }
    }

    // MARK: Drives

    @ViewBuilder
    private var driveRows: some View {
        if store.drives.isEmpty {
            note("No drives connected")
        } else {
            ForEach(store.drives, id: \.path) { drive in
                ControlsRow(
                    symbol: "externaldrive.fill",
                    name: drive.name,
                    subtitle: drive.free.map { "\(Self.sizeFormatter.string(fromByteCount: $0)) free" }
                ) { _ in
                    Button { store.eject(drive) } label: {
                        Image(systemName: "eject.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.foreground.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(palette.foreground.opacity(0.10)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(palette.foreground.opacity(0.45))
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}

// MARK: - Tab

struct ControlsTabView: View {
    @Environment(\.nubrixPalette) private var palette
    @ObservedObject private var store = ControlsStore.shared
    @AppStorage("controlsListTab") private var tabRaw = ControlsListTab.wifi.rawValue

    private var hasDrives: Bool { !store.drives.isEmpty }

    private var tab: Binding<ControlsListTab> {
        Binding(
            get: { ControlsListTab.effective(tabRaw, hasDrives: hasDrives) },
            set: { tabRaw = $0.rawValue }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            ControlsLevels(store: store, tab: tab)
                .frame(width: 244, alignment: .topLeading)
                .padding(.trailing, 18)
                .padding(.top, 4)
            Rectangle()
                .fill(ControlsStyle.hairline(palette))
                .frame(width: 1)
                .padding(.top, 6)
                .padding(.bottom, 10)
            VStack(alignment: .leading, spacing: 8) {
                ControlsSegmented(selection: tab, tabs: ControlsListTab.tabs(hasDrives: hasDrives))
                ControlsList(store: store, tab: tab)
            }
            .padding(.leading, 16)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            store.start()
            store.setWiFiVisible(tab.wrappedValue == .wifi)
        }
        .onChange(of: tabRaw) { _, _ in store.setWiFiVisible(tab.wrappedValue == .wifi) }
        .onChange(of: hasDrives) { _, _ in store.setWiFiVisible(tab.wrappedValue == .wifi) }
        .onDisappear { store.stop() }
    }
}
