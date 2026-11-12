import XCTest
@testable import Nubrix

final class ThemeColorTests: XCTestCase {
    func testHexRoundTrip() {
        XCTAssertEqual(ThemeColor(hex: "#1C1C1E").hex, "#1C1C1E")
        XCTAssertEqual(ThemeColor(hex: "ff8800").hex, "#FF8800")
        XCTAssertEqual(ThemeColor(hex: "#11223380").hex, "#11223380")
    }

    func testInvalidHexIsBlack() {
        XCTAssertEqual(ThemeColor(hex: "nope"), .black)
    }

    func testSRGBConversion() {
        let c = ThemeColor(NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.5))
        XCTAssertEqual(c.red, 0.2, accuracy: 0.001)
        XCTAssertEqual(c.green, 0.4, accuracy: 0.001)
        XCTAssertEqual(c.blue, 0.6, accuracy: 0.001)
        XCTAssertEqual(c.alpha, 0.5, accuracy: 0.001)
    }

    func testLuminance() {
        XCTAssertEqual(ThemeColor.black.luminance, 0, accuracy: 0.0001)
        XCTAssertEqual(ThemeColor.white.luminance, 1, accuracy: 0.0001)
    }
}

final class NubrixThemeTests: XCTestCase {
    func testCodableRoundTrip() throws {
        for theme in NubrixTheme.builtIns {
            let data = try JSONEncoder().encode(theme)
            XCTAssertEqual(try JSONDecoder().decode(NubrixTheme.self, from: data), theme)
        }
    }

    func testMinimalJSONFillsDefaults() throws {
        let theme = try JSONDecoder().decode(NubrixTheme.self, from: Data(#"{"id":"x","name":"X"}"#.utf8))
        XCTAssertEqual(theme.id, "x")
        XCTAssertEqual(theme.name, "X")
        XCTAssertEqual(theme.background, .solid)
        XCTAssertEqual(theme.opacity, 1)
        XCTAssertNil(theme.accentColor)
        XCTAssertFalse(theme.showsBorder)
    }

    func testResolvedForeground() {
        var t = NubrixTheme(id: "t", name: "t", primaryColor: .black)
        XCTAssertEqual(t.resolvedForeground, .light)
        t.primaryColor = .white
        XCTAssertEqual(t.resolvedForeground, .dark)
        t.opacity = 0.3
        XCTAssertEqual(t.resolvedForeground, .light)
        t.opacity = 1
        t.background = .blur
        XCTAssertEqual(t.resolvedForeground, .light)
        t.foreground = .dark
        XCTAssertEqual(t.resolvedForeground, .dark)
        XCTAssertEqual(t.colorScheme, .light)
    }

    func testBuiltInsUniqueAndClassicFirst() {
        let ids = NubrixTheme.builtIns.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.first, "classic")
        XCTAssertTrue(ids.dropFirst().allSatisfy { $0.hasPrefix("builtin.") })
        let c = NubrixTheme.classic
        XCTAssertEqual(c.background, .solid)
        XCTAssertEqual(c.primaryColor, .black)
        XCTAssertEqual(c.opacity, 1)
        XCTAssertEqual(c.resolvedForeground, .light)
        XCTAssertEqual(c.colorScheme, .dark)
        XCTAssertFalse(c.isTranslucent)
        XCTAssertFalse(c.showsBorder)
        XCTAssertNil(c.accentColor)
    }
}

final class ThemeStoreResolveTests: XCTestCase {
    private let custom = ThemeStore.makeCustom(from: NubrixTheme.builtIns[7])
    private let saved = [NubrixTheme(id: "u1", name: "Mine", primaryColor: ThemeColor(hex: "#336699"))]

    func testUnknownIDFallsBackToClassic() {
        XCTAssertEqual(ThemeStore.resolve(selectedID: "zzz", custom: custom, saved: saved), .classic)
    }

    func testBuiltInSavedAndCustom() {
        XCTAssertEqual(ThemeStore.resolve(selectedID: "builtin.paper", custom: custom, saved: saved).name, "Paper")
        XCTAssertEqual(ThemeStore.resolve(selectedID: "u1", custom: custom, saved: saved).name, "Mine")
        let c = ThemeStore.resolve(selectedID: "custom", custom: custom, saved: saved)
        XCTAssertEqual(c.id, "custom")
        XCTAssertEqual(c.name, "Custom")
        XCTAssertEqual(c.primaryColor, NubrixTheme.builtIns[7].primaryColor)
    }

    func testDeletedSavedSelectionFallsBackToClassic() {
        XCTAssertEqual(ThemeStore.resolve(selectedID: "u1", custom: custom, saved: []), .classic)
    }
}
