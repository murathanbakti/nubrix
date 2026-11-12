import AppKit
import SwiftUI
import XCTest
@testable import Nubrix

final class ThemePaletteStatusTests: XCTestCase {
    private func contrast(_ a: Color, _ b: ThemeColor) -> Double {
        let la = ThemeColor(NSColor(a)).luminance
        let lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func paper() -> NubrixTheme {
        NubrixTheme.builtIns.first { $0.id == "builtin.paper" }!
    }

    func testStatusColorsAreReadableOnLightThemes() {
        let theme = paper()
        XCTAssertEqual(theme.resolvedForeground, .dark)
        let palette = ThemePalette(theme: theme)
        let colors: [(String, Color)] = [
            ("danger", palette.danger), ("dangerText", palette.dangerText),
            ("warning", palette.warning), ("diffAdded", palette.diffAdded),
            ("diffRemoved", palette.diffRemoved),
        ]
        for (name, color) in colors {
            XCTAssertGreaterThanOrEqual(contrast(color, theme.primaryColor), 4.5, name)
        }
    }

    func testRiskyAllowButtonTextIsReadableOnLightThemes() {
        let theme = paper()
        let red = ThemeColor(NSColor.systemRed)
        let button = red.mixed(with: theme.primaryColor, amount: 0.72) // red at 28 % over the paper fill
        XCTAssertGreaterThanOrEqual(contrast(ThemePalette(theme: theme).dangerButtonText, button), 4.5)
    }

    func testClassicKeepsTheOriginalBrightTints() {
        let palette = ThemePalette(theme: .classic)
        let danger = ThemeColor(NSColor(palette.danger))
        XCTAssertEqual(danger.red, 1, accuracy: 0.01)
        XCTAssertEqual(danger.green, 0.42, accuracy: 0.01)
        XCTAssertEqual(danger.blue, 0.4, accuracy: 0.01)
        let added = ThemeColor(NSColor(palette.diffAdded))
        XCTAssertEqual(added.green, 0.85, accuracy: 0.01)
    }
}
