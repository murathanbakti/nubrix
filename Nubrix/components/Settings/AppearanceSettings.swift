import AVFoundation
import Defaults
import SwiftUI

struct AppearanceSettings: View {
    @Default(.mirrorShape) var mirrorShape
    @Default(.sliderColor) var sliderColor
    @Default(.showMirror) var showMirror
    @Default(.useCustomAccentColor) var useCustomAccentColor

    @State private var hasCamera = true
    @State private var customAccentColor: Color = .accentColor
    @State private var selectedPresetColor: PresetAccentColor?

    enum PresetAccentColor: String, CaseIterable, Identifiable {
        case blue = "Blue"
        case purple = "Purple"
        case pink = "Pink"
        case red = "Red"
        case orange = "Orange"
        case yellow = "Yellow"
        case green = "Green"
        case graphite = "Graphite"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .blue: return Color(red: 0.0, green: 0.478, blue: 1.0)
            case .purple: return Color(red: 0.686, green: 0.322, blue: 0.871)
            case .pink: return Color(red: 1.0, green: 0.176, blue: 0.333)
            case .red: return Color(red: 1.0, green: 0.271, blue: 0.227)
            case .orange: return Color(red: 1.0, green: 0.584, blue: 0.0)
            case .yellow: return Color(red: 1.0, green: 0.8, blue: 0.0)
            case .green: return Color(red: 0.4, green: 0.824, blue: 0.176)
            case .graphite: return Color(red: 0.557, green: 0.557, blue: 0.576)
            }
        }
    }

    var body: some View {
        Form {
            accentSection
            notchSection
            mediaSection
            mirrorSection
        }
        .settingsPage(.appearance)
        .onAppear {
            hasCamera = AVCaptureDevice.default(for: .video) != nil
            loadCustomColor()
            if !useCustomAccentColor {
                selectedPresetColor = nil
            }
        }
    }

    private var accentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Accent color", selection: $useCustomAccentColor) {
                    Text("System").tag(false)
                    Text("Custom").tag(true)
                }
                .pickerStyle(.segmented)

                if !useCustomAccentColor {
                    HStack(spacing: 12) {
                        AccentCircleButton(
                            isSelected: true,
                            color: .accentColor,
                            isSystemDefault: true
                        ) {}

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Using system accent")
                                .font(.body)
                            Text("Your macOS accent color")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Presets")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(PresetAccentColor.allCases) { preset in
                                AccentCircleButton(
                                    isSelected: selectedPresetColor == preset,
                                    color: preset.color,
                                    isMulticolor: false
                                ) {
                                    selectedPresetColor = preset
                                    customAccentColor = preset.color
                                    saveCustomColor(preset.color)
                                }
                            }
                            Spacer()
                        }

                        Divider()
                            .padding(.vertical, 4)

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pick a color")
                                    .font(.body)
                                Text("Choose any color")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            ColorPicker(selection: Binding(
                                get: { customAccentColor },
                                set: { newColor in
                                    customAccentColor = newColor
                                    selectedPresetColor = nil
                                    saveCustomColor(newColor)
                                }
                            ), supportsOpacity: false) {
                                ZStack {
                                    Circle()
                                        .fill(customAccentColor)
                                        .frame(width: 32, height: 32)

                                    if selectedPresetColor == nil {
                                        Circle()
                                            .strokeBorder(.primary.opacity(0.3), lineWidth: 2)
                                            .frame(width: 32, height: 32)
                                    }
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Accent color")
        } footer: {
            SettingsFooter("Use your macOS accent color or pick your own.")
        }
    }

    private var notchSection: some View {
        Section {
            Defaults.Toggle(key: .settingsIconInNotch) {
                Text("Show settings icon in notch")
            }
            Defaults.Toggle(key: .enableShadow) {
                Text("Enable window shadow")
            }
            Defaults.Toggle(key: .cornerRadiusScaling) {
                Text("Corner radius scaling")
            }
        } header: {
            Text("Notch")
        }
    }

    private var mediaSection: some View {
        Section {
            Defaults.Toggle(key: .coloredSpectrogram) {
                Text("Colored spectrogram")
            }
            Defaults.Toggle(key: .playerColorTinting) {
                Text("Player tinting")
            }
            Defaults.Toggle(key: .lightingEffect) {
                Text("Blur effect behind album art")
            }
            Picker("Slider color", selection: $sliderColor) {
                ForEach(SliderColorEnum.allCases, id: \.self) { option in
                    Text(option.rawValue)
                }
            }
        } header: {
            Text("Media")
        }
    }

    private var mirrorSection: some View {
        Section {
            Defaults.Toggle(key: .showMirror) {
                Text("Enable mirror")
            }
            .disabled(!hasCamera)
            Picker("Mirror shape", selection: $mirrorShape) {
                Text("Circle")
                    .tag(MirrorShapeEnum.circle)
                Text("Square")
                    .tag(MirrorShapeEnum.rectangle)
            }
            .disabled(!showMirror)
            Defaults.Toggle(key: .showNotHumanFace) {
                Text("Show face animation while idle")
            }
            .disabled(!showMirror)
        } header: {
            Text("Mirror")
        } footer: {
            SettingsFooter(hasCamera ? "Opens a camera preview from the notch." : "No camera found on this Mac.")
        }
    }

    private func forceUiUpdate() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("AccentColorChanged"), object: nil)
        }
    }

    private func saveCustomColor(_ color: Color) {
        let nsColor = NSColor(color)
        if let colorData = try? NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false) {
            Defaults[.customAccentColorData] = colorData
        }
        forceUiUpdate()
    }

    private func loadCustomColor() {
        if let colorData = Defaults[.customAccentColorData],
           let nsColor = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
            customAccentColor = Color(nsColor: nsColor)

            selectedPresetColor = nil
            for preset in PresetAccentColor.allCases {
                if colorsAreEqual(Color(nsColor: nsColor), preset.color) {
                    selectedPresetColor = preset
                    break
                }
            }
        }
    }

    private func colorsAreEqual(_ color1: Color, _ color2: Color) -> Bool {
        let nsColor1 = NSColor(color1).usingColorSpace(.sRGB) ?? NSColor(color1)
        let nsColor2 = NSColor(color2).usingColorSpace(.sRGB) ?? NSColor(color2)

        return abs(nsColor1.redComponent - nsColor2.redComponent) < 0.01 &&
               abs(nsColor1.greenComponent - nsColor2.greenComponent) < 0.01 &&
               abs(nsColor1.blueComponent - nsColor2.blueComponent) < 0.01
    }
}

struct AccentCircleButton: View {
    let isSelected: Bool
    let color: Color
    var isSystemDefault: Bool = false
    var isMulticolor: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)

                Circle()
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    .frame(width: 32, height: 32)

                if isSelected {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
            }
        }
        .buttonStyle(.plain)
        .help(isSystemDefault ? "Use your macOS accent color" : "")
    }
}
