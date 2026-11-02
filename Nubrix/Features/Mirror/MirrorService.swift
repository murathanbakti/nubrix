import AppKit
import Combine
import Defaults
import KeyboardShortcuts

@MainActor
enum MirrorService {
    private static var observers = Set<AnyCancellable>()

    static func start() {
        observers.removeAll()
        KeyboardShortcuts.onKeyDown(for: .toggleMirror) {
            Task { @MainActor in MirrorMode.shared.toggleUnderMouse() }
        }
        Defaults.publisher(.showMirror, options: [])
            .receive(on: RunLoop.main)
            .sink { change in
                guard !change.newValue else { return }
                MainActor.assumeIsolated { MirrorMode.shared.exit(animated: false) }
            }
            .store(in: &observers)
    }

    static func stop() {
        observers.removeAll()
        MirrorMode.shared.exit(animated: false)
    }
}
