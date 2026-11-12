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
}

enum WhatsNewPolicy {
    static func shouldShow(currentVersion: String, lastSeenVersion: String?, isFirstLaunch: Bool, hasNotes: Bool) -> Bool {
        guard !isFirstLaunch, hasNotes else { return false }
        return lastSeenVersion != currentVersion
    }
}
