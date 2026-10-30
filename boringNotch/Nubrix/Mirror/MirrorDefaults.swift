import Defaults
import KeyboardShortcuts

extension Defaults.Keys {
    static let mirrorFlipped = Key<Bool>("mirrorFlipped", default: true)
    static let mirrorLarge = Key<Bool>("mirrorLarge", default: false)
}

extension KeyboardShortcuts.Name {
    static let toggleMirror = Self("toggleMirror", default: .init(.m, modifiers: [.control, .option]))
}
