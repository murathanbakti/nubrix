import AppKit
import Defaults
import SwiftUI

enum ThemeBackgroundStyle: String, Codable, CaseIterable {
    case solid, gradient, blur
}

enum ThemeBlurMaterial: String, Codable, CaseIterable {
    case ultraThin, thin, regular, thick, hud

    var material: NSVisualEffectView.Material {
        switch self {
        case .ultraThin: return .underWindowBackground
        case .thin: return .menu
        case .regular: return .popover
        case .thick: return .sidebar
        case .hud: return .hudWindow
        }
    }
}

enum ThemeForeground: String, Codable, CaseIterable {
    /// `light` means light (white) content, meant for dark backgrounds.
    case auto, light, dark
}

enum ThemeIconColor: String, Codable, CaseIterable {
    case text, accent, custom
}

struct NubrixTheme: Codable, Hashable, Identifiable, Defaults.Serializable {
    var id: String
    var name: String
    var background: ThemeBackgroundStyle
    var primaryColor: ThemeColor
    var secondaryColor: ThemeColor
    var gradientAngle: Double
    var opacity: Double
    var blurMaterial: ThemeBlurMaterial
    var foreground: ThemeForeground
    var iconColor: ThemeIconColor
    var customIconColor: ThemeColor
    var accentColor: ThemeColor?
    var showsBorder: Bool
    var borderOpacity: Double

    init(
        id: String,
        name: String,
        background: ThemeBackgroundStyle = .solid,
        primaryColor: ThemeColor = .black,
        secondaryColor: ThemeColor = .black,
        gradientAngle: Double = 135,
        opacity: Double = 1,
        blurMaterial: ThemeBlurMaterial = .regular,
        foreground: ThemeForeground = .auto,
        iconColor: ThemeIconColor = .text,
        customIconColor: ThemeColor = .white,
        accentColor: ThemeColor? = nil,
        showsBorder: Bool = false,
        borderOpacity: Double = 0.18
    ) {
        self.id = id
        self.name = name
        self.background = background
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.gradientAngle = gradientAngle
        self.opacity = opacity
        self.blurMaterial = blurMaterial
        self.foreground = foreground
        self.iconColor = iconColor
        self.customIconColor = customIconColor
        self.accentColor = accentColor
        self.showsBorder = showsBorder
        self.borderOpacity = borderOpacity
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, background, primaryColor, secondaryColor, gradientAngle, opacity
        case blurMaterial, foreground, iconColor, customIconColor, accentColor
        case showsBorder, borderOpacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NubrixTheme.classic
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? d.id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? d.name
        background = try c.decodeIfPresent(ThemeBackgroundStyle.self, forKey: .background) ?? d.background
        primaryColor = try c.decodeIfPresent(ThemeColor.self, forKey: .primaryColor) ?? d.primaryColor
        secondaryColor = try c.decodeIfPresent(ThemeColor.self, forKey: .secondaryColor) ?? d.secondaryColor
        gradientAngle = try c.decodeIfPresent(Double.self, forKey: .gradientAngle) ?? d.gradientAngle
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        blurMaterial = try c.decodeIfPresent(ThemeBlurMaterial.self, forKey: .blurMaterial) ?? d.blurMaterial
        foreground = try c.decodeIfPresent(ThemeForeground.self, forKey: .foreground) ?? d.foreground
        iconColor = try c.decodeIfPresent(ThemeIconColor.self, forKey: .iconColor) ?? d.iconColor
        customIconColor = try c.decodeIfPresent(ThemeColor.self, forKey: .customIconColor) ?? d.customIconColor
        accentColor = try c.decodeIfPresent(ThemeColor.self, forKey: .accentColor)
        showsBorder = try c.decodeIfPresent(Bool.self, forKey: .showsBorder) ?? d.showsBorder
        borderOpacity = try c.decodeIfPresent(Double.self, forKey: .borderOpacity) ?? d.borderOpacity
    }

    /// Never `.auto`.
    var resolvedForeground: ThemeForeground {
        if foreground != .auto { return foreground }
        switch background {
        case .blur:
            return .light
        case .solid, .gradient:
            if opacity < 0.5 { return .light }
            let lum = background == .solid
                ? primaryColor.luminance
                : (primaryColor.luminance + secondaryColor.luminance) / 2
            return lum > 0.5 ? .dark : .light
        }
    }

    var colorScheme: ColorScheme {
        resolvedForeground == .light ? .dark : .light
    }

    var isTranslucent: Bool {
        background == .blur || opacity < 0.95
    }

    /// Flat color for places that cannot draw a blur (e.g. Canvas).
    var approximateFill: Color {
        switch background {
        case .solid:
            return primaryColor.color.opacity(opacity)
        case .gradient:
            return primaryColor.mixed(with: secondaryColor).color.opacity(opacity)
        case .blur:
            return primaryColor.color.opacity(max(opacity, 0.75))
        }
    }

    static let classic = NubrixTheme(id: "classic", name: "Classic", foreground: .light)

    static let builtIns: [NubrixTheme] = [
        classic,
        NubrixTheme(id: "builtin.graphite", name: "Graphite",
                    primaryColor: ThemeColor(hex: "#1C1C1E"), foreground: .light),
        NubrixTheme(id: "builtin.midnight", name: "Midnight", background: .gradient,
                    primaryColor: ThemeColor(hex: "#0B1430"), secondaryColor: ThemeColor(hex: "#1E2A5A"),
                    foreground: .light),
        NubrixTheme(id: "builtin.aurora", name: "Aurora", background: .gradient,
                    primaryColor: ThemeColor(hex: "#0F2027"), secondaryColor: ThemeColor(hex: "#2C5364"),
                    foreground: .light, accentColor: ThemeColor(hex: "#2DD4BF")),
        NubrixTheme(id: "builtin.frosted", name: "Frosted", background: .blur,
                    primaryColor: ThemeColor(hex: "#0A0A0C"), opacity: 0.25,
                    blurMaterial: .regular, foreground: .light, showsBorder: true),
        NubrixTheme(id: "builtin.glass-light", name: "Glass Light", background: .blur,
                    primaryColor: .white, opacity: 0.2, blurMaterial: .thin,
                    foreground: .dark, showsBorder: true),
        NubrixTheme(id: "builtin.clear", name: "Clear", primaryColor: .black, opacity: 0.35,
                    foreground: .light, showsBorder: true),
        NubrixTheme(id: "builtin.paper", name: "Paper", primaryColor: ThemeColor(hex: "#F2F2F7"),
                    foreground: .dark),
    ]
}
