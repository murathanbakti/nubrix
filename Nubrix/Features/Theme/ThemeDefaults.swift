import Defaults

extension Defaults.Keys {
    static let selectedThemeID = Key<String>("selectedThemeID", default: "classic")
    static let customTheme = Key<NubrixTheme>("customTheme", default: ThemeStore.makeCustom(from: .classic))
    static let savedThemes = Key<[NubrixTheme]>("savedThemes", default: [])
    static let themeAppliesToClosedNotch = Key<Bool>("themeAppliesToClosedNotch", default: false)
    static let themeAppliesToExtensions = Key<Bool>("themeAppliesToExtensions", default: true)
}
