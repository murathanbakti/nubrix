import Foundation

struct WhatsNewItem: Equatable, Identifiable {
    let symbol: String
    let title: String
    let body: String
    var id: String { title }
}

struct WhatsNewNotes: Equatable {
    let title: String
    let items: [WhatsNewItem]
    let footer: String?
    /// Settings tab the primary button opens. `nil` hides the primary button.
    let actionTab: SettingsTab?
    let actionTitle: String?
}

enum WhatsNewCatalog {
    static let notes: [String: WhatsNewNotes] = [
        "0.5.0": WhatsNewNotes(
            title: "What's new in Nubrix 0.5.0",
            items: [
                WhatsNewItem(
                    symbol: "paintpalette",
                    title: "Themes",
                    body: "Give the notch your own look in Settings, Theme. Pick a solid color, a gradient or a frosted blur, and make it as transparent as you like."),
                WhatsNewItem(
                    symbol: "textformat",
                    title: "Text and icon colors",
                    body: "Choose light or dark text, icons that match your text, your accent or any color, and an accent just for the theme."),
                WhatsNewItem(
                    symbol: "square.grid.2x2",
                    title: "Eight built-in themes",
                    body: "Classic, Graphite, Midnight, Aurora, Frosted, Glass Light, Clear and Paper. Save your own and switch any time."),
                WhatsNewItem(
                    symbol: "rectangle.on.rectangle",
                    title: "Side panels follow along",
                    body: "Side panels and the Vitrin panel use your theme too. The closed notch stays black unless you turn it on."),
            ],
            footer: "Classic is the default, so nothing changes until you pick a theme.",
            actionTab: .theme,
            actionTitle: "Open Theme Settings"),
    ]

    static func notes(for version: String) -> WhatsNewNotes? { notes[version] }

    /// The newest notes at or below `current` that are newer than `lastSeen`, so a user
    /// who skips a version (0.4.0 straight to 0.5.1) still sees the 0.5.0 notes.
    /// `lastSeen == nil` means any notes at or below `current`.
    static func latestNotes(upTo current: String, after lastSeen: String?) -> WhatsNewNotes? {
        notes.keys
            .filter { version in
                guard compare(version, current) != .orderedDescending else { return false }
                guard let lastSeen else { return true }
                return compare(version, lastSeen) == .orderedDescending
            }
            .max { compare($0, $1) == .orderedAscending }
            .flatMap { notes[$0] }
    }

    /// Numeric comparison of dotted versions ("0.10.0" > "0.9.1"; missing parts count as 0).
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

enum WhatsNewPolicy {
    static func shouldShow(currentVersion: String, lastSeenVersion: String?, isFirstLaunch: Bool, hasNotes: Bool) -> Bool {
        guard !isFirstLaunch, hasNotes else { return false }
        return lastSeenVersion != currentVersion
    }
}
