import Combine
import Defaults
import Foundation

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    static let customID = "custom"

    @Published private(set) var current: NubrixTheme
    @Published private(set) var appliesToClosedNotch: Bool
    @Published private(set) var appliesToExtensions: Bool
    @Published private(set) var savedThemes: [NubrixTheme]
    @Published private(set) var customTheme: NubrixTheme

    private var cancellables = Set<AnyCancellable>()

    var allThemes: [NubrixTheme] { NubrixTheme.builtIns + savedThemes + [customTheme] }

    init() {
        current = ThemeStore.resolve(
            selectedID: Defaults[.selectedThemeID],
            custom: Defaults[.customTheme],
            saved: Defaults[.savedThemes]
        )
        appliesToClosedNotch = Defaults[.themeAppliesToClosedNotch]
        appliesToExtensions = Defaults[.themeAppliesToExtensions]
        savedThemes = Defaults[.savedThemes]
        customTheme = Defaults[.customTheme]

        Defaults.publisher(keys: .selectedThemeID, .customTheme, .savedThemes, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        Defaults.publisher(keys: .themeAppliesToClosedNotch, .themeAppliesToExtensions, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    private func refresh() {
        let saved = Defaults[.savedThemes]
        let custom = Defaults[.customTheme]
        savedThemes = saved
        customTheme = custom
        current = ThemeStore.resolve(selectedID: Defaults[.selectedThemeID], custom: custom, saved: saved)
        appliesToClosedNotch = Defaults[.themeAppliesToClosedNotch]
        appliesToExtensions = Defaults[.themeAppliesToExtensions]
    }

    // MARK: - Pure logic

    nonisolated static func resolve(selectedID: String, custom: NubrixTheme, saved: [NubrixTheme]) -> NubrixTheme {
        if selectedID == customID { return makeCustom(from: custom) }
        if let builtIn = NubrixTheme.builtIns.first(where: { $0.id == selectedID }) { return builtIn }
        if let match = saved.first(where: { $0.id == selectedID }) { return match }
        return .classic
    }

    nonisolated static func makeCustom(from theme: NubrixTheme) -> NubrixTheme {
        var t = theme
        t.id = customID
        t.name = "Custom"
        return t
    }

    // MARK: - Mutations

    func theme(withID id: String) -> NubrixTheme {
        ThemeStore.resolve(selectedID: id, custom: customTheme, saved: savedThemes)
    }

    func select(_ id: String) {
        Defaults[.selectedThemeID] = theme(withID: id).id
    }

    /// Edits the custom slot. The first edit of a non-custom theme copies it into the custom slot and selects it.
    func updateCustom(_ edit: (inout NubrixTheme) -> Void) {
        var t = Defaults[.selectedThemeID] == ThemeStore.customID
            ? Defaults[.customTheme]
            : ThemeStore.makeCustom(from: current)
        edit(&t)
        t.id = ThemeStore.customID
        t.name = "Custom"
        Defaults[.customTheme] = t
        Defaults[.selectedThemeID] = ThemeStore.customID
    }

    @discardableResult
    func saveCurrent(as name: String) -> NubrixTheme {
        var t = current
        t.id = UUID().uuidString
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        t.name = trimmed.isEmpty ? "Theme" : trimmed
        Defaults[.savedThemes].append(t)
        Defaults[.selectedThemeID] = t.id
        return t
    }

    func rename(id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = Defaults[.savedThemes].firstIndex(where: { $0.id == id }) else { return }
        Defaults[.savedThemes][i].name = trimmed
    }

    func delete(id: String) {
        guard Defaults[.savedThemes].contains(where: { $0.id == id }) else { return }
        Defaults[.savedThemes].removeAll { $0.id == id }
        if Defaults[.selectedThemeID] == id { Defaults[.selectedThemeID] = NubrixTheme.classic.id }
    }

    func resetToClassic() {
        Defaults[.customTheme] = ThemeStore.makeCustom(from: .classic)
        Defaults[.selectedThemeID] = NubrixTheme.classic.id
    }
}
