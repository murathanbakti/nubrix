import AppKit
import Defaults
import SwiftUI

struct ThemeColor: Codable, Hashable, Defaults.Serializable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(_ nsColor: NSColor) {
        let c = nsColor.usingColorSpace(.sRGB) ?? NSColor.black.usingColorSpace(.sRGB) ?? nsColor
        self.init(
            red: Double(c.redComponent),
            green: Double(c.greenComponent),
            blue: Double(c.blueComponent),
            alpha: Double(c.alphaComponent)
        )
    }

    /// Accepts "RRGGBB" or "RRGGBBAA", with or without a leading "#". Invalid input yields black.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        guard (s.count == 6 || s.count == 8), Scanner(string: s).scanHexInt64(&value) else {
            self.init(red: 0, green: 0, blue: 0)
            return
        }
        if s.count == 6 {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        } else {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                alpha: Double(value & 0xFF) / 255
            )
        }
    }

    static let black = ThemeColor(red: 0, green: 0, blue: 0)
    static let white = ThemeColor(red: 1, green: 1, blue: 1)

    /// "#RRGGBB", or "#RRGGBBAA" when not fully opaque.
    var hex: String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        let base = String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
        return alpha < 1 ? base + String(format: "%02X", byte(alpha)) : base
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// WCAG relative luminance (0 = black, 1 = white).
    var luminance: Double {
        func lin(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    func mixed(with other: ThemeColor, amount: Double = 0.5) -> ThemeColor {
        let t = min(max(amount, 0), 1)
        return ThemeColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }
}
