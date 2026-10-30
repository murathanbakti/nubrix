import Defaults
import KeyboardShortcuts

extension Defaults.Keys {
    static let mirrorSizeIndex = Key<Int>("mirrorSizeIndex", default: 1)
    static let mirrorFlipped = Key<Bool>("mirrorFlipped", default: true)
}

extension KeyboardShortcuts.Name {
    static let toggleMirror = Self("toggleMirror", default: .init(.m, modifiers: [.control, .option]))
}
