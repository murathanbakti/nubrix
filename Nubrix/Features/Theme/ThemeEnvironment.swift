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
