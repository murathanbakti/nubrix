import SwiftUI

private struct NubrixThemeKey: EnvironmentKey {
    static let defaultValue: NubrixTheme = .classic
}

extension EnvironmentValues {
    var nubrixTheme: NubrixTheme {
        get { self[NubrixThemeKey.self] }
        set { self[NubrixThemeKey.self] = newValue }
    }

    var nubrixPalette: ThemePalette { ThemePalette(theme: nubrixTheme) }
}

struct ThemePalette {
    let theme: NubrixTheme

    private var base: Color { theme.resolvedForeground == .light ? .white : .black }

    var foreground: Color { base }
    var secondary: Color { base.opacity(0.6) }
    var tertiary: Color { base.opacity(0.35) }
    var surface: Color { base.opacity(0.08) }
    var surfaceStrong: Color { base.opacity(0.14) }
    var separator: Color { base.opacity(0.12) }
    /// Flat stand-in for the notch background, for layers that must hide what is behind them.
    var backing: Color { theme.approximateFill }

    // Status colors. Dark themes keep the original bright tints; light themes get
    // darker shades so warnings stay readable (WCAG AA on #F2F2F7).
    private var onDark: Bool { theme.resolvedForeground == .light }
    /// Risk text and icons.
    var danger: Color { onDark ? Color(red: 1, green: 0.42, blue: 0.4) : Color(red: 0.72, green: 0.1, blue: 0.1) }
    /// Text of a command flagged as risky.
    var dangerText: Color { onDark ? Color(red: 1, green: 0.62, blue: 0.6) : Color(red: 0.62, green: 0.08, blue: 0.08) }
    /// Text on the soft red "Allow" button of a risky request.
    var dangerButtonText: Color { onDark ? Color(red: 1, green: 0.55, blue: 0.52) : Color(red: 0.66, green: 0.08, blue: 0.08) }
    var warning: Color { onDark ? .orange : Color(red: 0.66, green: 0.34, blue: 0) }
    var diffAdded: Color { onDark ? Color(red: 0.55, green: 0.85, blue: 0.6) : Color(red: 0.08, green: 0.45, blue: 0.18) }
    var diffRemoved: Color { onDark ? Color(red: 1, green: 0.58, blue: 0.56) : Color(red: 0.68, green: 0.1, blue: 0.1) }

    var accent: Color { theme.accentColor?.color ?? Color.effectiveAccent }

    var icon: Color {
        switch theme.iconColor {
        case .text: return foreground
        case .accent: return accent
        case .custom: return theme.customIconColor.color
        }
    }
}

extension View {
    func nubrixTheme(_ theme: NubrixTheme) -> some View {
        environment(\.nubrixTheme, theme)
            .preferredColorScheme(theme.colorScheme)
    }

    func themedIcon() -> some View {
        modifier(ThemedIconModifier())
    }
}

private struct ThemedIconModifier: ViewModifier {
    @Environment(\.nubrixTheme) private var theme

    func body(content: Content) -> some View {
        content.foregroundStyle(ThemePalette(theme: theme).icon)
    }
}
