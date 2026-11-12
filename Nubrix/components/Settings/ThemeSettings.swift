import Defaults
import SwiftUI

struct ThemeSettings: View {
    @ObservedObject private var store = ThemeStore.shared
    @Default(.themeAppliesToClosedNotch) private var appliesToClosedNotch
    @Default(.themeAppliesToExtensions) private var appliesToExtensions

    @State private var showingSave = false
    @State private var saveName = ""
    @State private var renameTarget: NubrixTheme?
    @State private var renameText = ""

    private var theme: NubrixTheme { store.current }

    var body: some View {
        Form {
            previewSection
            themesSection
            backgroundSection
            contentSection
            scopeSection
            actionsSection
        }
        .settingsPage(.theme)
        .alert("Save as Theme", isPresented: $showingSave) {
            TextField("Name", text: $saveName)
            Button("Save") { store.saveCurrent(as: saveName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this look a name to keep it in your themes.")
        }
        .alert("Rename Theme", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let t = renameTarget { store.rename(id: t.id, to: renameText) }
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    // MARK: - Bindings

    private func binding<T>(_ keyPath: WritableKeyPath<NubrixTheme, T>) -> Binding<T> {
        Binding(
            get: { store.current[keyPath: keyPath] },
            set: { value in store.updateCustom { $0[keyPath: keyPath] = value } }
        )
    }

    private func colorBinding(_ keyPath: WritableKeyPath<NubrixTheme, ThemeColor>) -> Binding<Color> {
        Binding(
            get: { store.current[keyPath: keyPath].color },
            set: { color in store.updateCustom { $0[keyPath: keyPath] = ThemeColor(NSColor(color)) } }
        )
    }

    private var customAccentBinding: Binding<Bool> {
        Binding(
            get: { store.current.accentColor != nil },
            set: { on in
                store.updateCustom {
                    $0.accentColor = on ? ($0.accentColor ?? ThemeColor(NSColor(Color.effectiveAccent))) : nil
                }
            }
        )
    }

    private var accentColorBinding: Binding<Color> {
        Binding(
            get: { store.current.accentColor?.color ?? .effectiveAccent },
            set: { color in store.updateCustom { $0.accentColor = ThemeColor(NSColor(color)) } }
        )
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    // MARK: - Sections

    private var previewSection: some View {
        Section {
            ThemePreview(theme: theme)
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } header: {
            Text("Preview")
        }
    }

    private var visibleThemes: [NubrixTheme] {
        var list = NubrixTheme.builtIns + store.savedThemes
        // Keep unsaved custom edits reachable after switching to another theme.
        if theme.id == ThemeStore.customID || store.customTheme != ThemeStore.makeCustom(from: .classic) {
            list.append(store.customTheme)
        }
        return list
    }

    private var themesSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 14)], spacing: 14) {
                ForEach(visibleThemes) { item in
                    ThemeSwatch(theme: item, isSelected: theme.id == item.id)
                        .onTapGesture { store.select(item.id) }
                        .contextMenu {
                            if store.savedThemes.contains(where: { $0.id == item.id }) {
                                Button("Rename…") {
                                    renameText = item.name
                                    renameTarget = item
                                }
                                Button("Delete", role: .destructive) { store.delete(id: item.id) }
                            }
                        }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Themes")
        } footer: {
            SettingsFooter("Editing any option below creates a Custom theme. Built-in themes are never changed.")
        }
    }

    private var backgroundSection: some View {
        Section {
            Picker("Style", selection: binding(\.background)) {
                Text("Solid").tag(ThemeBackgroundStyle.solid)
                Text("Gradient").tag(ThemeBackgroundStyle.gradient)
                Text("Blur").tag(ThemeBackgroundStyle.blur)
            }
            .pickerStyle(.segmented)

            ColorPicker(theme.background == .gradient ? "Start color" : "Color",
                        selection: colorBinding(\.primaryColor), supportsOpacity: false)
            if theme.background == .gradient {
                ColorPicker("End color", selection: colorBinding(\.secondaryColor), supportsOpacity: false)
                LabeledContent("Angle") {
                    HStack {
                        Slider(value: binding(\.gradientAngle), in: 0...360)
                        Text("\(Int(theme.gradientAngle))°").monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            if theme.background == .blur {
                Picker("Material", selection: binding(\.blurMaterial)) {
                    Text("Ultra thin").tag(ThemeBlurMaterial.ultraThin)
                    Text("Thin").tag(ThemeBlurMaterial.thin)
                    Text("Regular").tag(ThemeBlurMaterial.regular)
                    Text("Thick").tag(ThemeBlurMaterial.thick)
                    Text("HUD").tag(ThemeBlurMaterial.hud)
                }
            }
            LabeledContent("Opacity") {
                HStack {
                    Text("Clear").font(.caption).foregroundStyle(.secondary)
                    Slider(value: binding(\.opacity), in: 0...1)
                    Text("Solid").font(.caption).foregroundStyle(.secondary)
                    Text(percent(theme.opacity)).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Toggle("Border", isOn: binding(\.showsBorder))
            if theme.showsBorder {
                LabeledContent("Border opacity") {
                    HStack {
                        Slider(value: binding(\.borderOpacity), in: 0.05...1)
                        Text(percent(theme.borderOpacity)).monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
        } header: {
            Text("Background")
        } footer: {
            SettingsFooter("Lower opacity makes the notch more transparent.")
        }
    }

    private var contentSection: some View {
        Section {
            Picker("Text color", selection: binding(\.foreground)) {
                Text("Auto").tag(ThemeForeground.auto)
                Text("Light").tag(ThemeForeground.light)
                Text("Dark").tag(ThemeForeground.dark)
            }
            .pickerStyle(.segmented)

            Picker("Icon color", selection: binding(\.iconColor)) {
                Text("Match text").tag(ThemeIconColor.text)
                Text("Accent").tag(ThemeIconColor.accent)
                Text("Custom").tag(ThemeIconColor.custom)
            }
            .pickerStyle(.segmented)
            if theme.iconColor == .custom {
                ColorPicker("Custom icon color", selection: colorBinding(\.customIconColor), supportsOpacity: false)
            }

            Picker("Accent", selection: customAccentBinding) {
                Text("App accent").tag(false)
                Text("Custom").tag(true)
            }
            .pickerStyle(.segmented)
            if theme.accentColor != nil {
                ColorPicker("Accent color", selection: accentColorBinding, supportsOpacity: false)
            }
        } header: {
            Text("Content")
        }
    }

    private var scopeSection: some View {
        Section {
            Toggle("Apply to closed notch", isOn: $appliesToClosedNotch)
            Toggle("Apply to side panels", isOn: $appliesToExtensions)
        } header: {
            Text("Scope")
        } footer: {
            SettingsFooter("The hardware notch always stays black, so the closed notch only blends in when it keeps its default look.")
        }
    }

    private var actionsSection: some View {
        Section {
            HStack {
                Button("Save as Theme…") {
                    saveName = theme.id == ThemeStore.customID ? "" : theme.name
                    showingSave = true
                }
                Spacer()
                Button("Reset to Classic") { store.resetToClassic() }
            }
        }
    }
}

/// Mock open notch over a colorful sample wallpaper, so legibility and translucency can be judged.
struct ThemePreview: View {
    let theme: NubrixTheme

    private var palette: ThemePalette { ThemePalette(theme: theme) }
    private let shape = NotchShape(topCornerRadius: 12, bottomCornerRadius: 26)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.55, blue: 0.30),
                    Color(red: 0.86, green: 0.25, blue: 0.50),
                    Color(red: 0.25, green: 0.35, blue: 0.85),
                    Color(red: 0.20, green: 0.75, blue: 0.70)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle().fill(.white.opacity(0.55)).frame(width: 90, height: 90).blur(radius: 6).offset(x: -110, y: 36)
            Rectangle().fill(.yellow.opacity(0.6)).frame(width: 70, height: 70).rotationEffect(.degrees(20)).offset(x: 120, y: 30)

            notch
        }
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Theme preview")
    }

    private var notch: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                ForEach(["house.fill", "music.note", "calendar", "tray.fill"], id: \.self) { name in
                    Image(systemName: name).font(.system(size: 13, weight: .medium)).foregroundStyle(palette.icon)
                }
                Spacer()
                Circle().fill(palette.accent).frame(width: 8, height: 8)
            }
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(palette.surfaceStrong).frame(width: 44, height: 44)
                    .overlay(Image(systemName: "waveform").foregroundStyle(palette.icon))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Now Playing").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.foreground)
                    Text("Sample Artist").font(.system(size: 11)).foregroundStyle(palette.secondary)
                }
                Spacer()
                Text("Chip")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.foreground)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(palette.surface))
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: 300)
        .background(ThemeBackground(theme: theme, shape: shape, blending: .withinWindow))
    }
}

struct ThemeSwatch: View {
    let theme: NubrixTheme
    let isSelected: Bool

    private var palette: ThemePalette { ThemePalette(theme: theme) }
    private let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                LinearGradient(colors: [.orange, .pink, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(shape)
                ThemeBackground(theme: theme, shape: shape, blending: .withinWindow)
                Text("Aa").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.foreground)
                Circle().fill(palette.accent).frame(width: 7, height: 7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6)
            }
            .frame(height: 52)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .overlay(shape.inset(by: -3).strokeBorder(isSelected ? Color.effectiveAccent : .clear, lineWidth: 2))
            Text(theme.name).font(.caption).lineLimit(1)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
