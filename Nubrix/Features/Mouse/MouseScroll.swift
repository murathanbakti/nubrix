import CoreGraphics
import Defaults
import Foundation

// MARK: - Settings

enum MouseScrollMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case off
    case automatic
    case always

    var id: Self { self }

    var title: String {
        switch self {
        case .off: return "Off"
        case .automatic: return "When a mouse is connected"
        case .always: return "Always"
        }
    }
}

extension Defaults.Keys {
    static let mouseScrollMode = Key<MouseScrollMode>("mouseScrollMode", default: .off)
    static let mouseScrollReverseHorizontal = Key<Bool>("mouseScrollReverseHorizontal", default: true)
    static let mouseScrollIgnoredDevices = Key<[String]>("mouseScrollIgnoredDevices", default: [])
}

struct MouseScrollSettings: Equatable {
    var mode: MouseScrollMode
    var reverseHorizontal: Bool
    var ignoredDevices: Set<String> = []

    static func current() -> MouseScrollSettings {
        MouseScrollSettings(
            mode: Defaults[.mouseScrollMode],
            reverseHorizontal: Defaults[.mouseScrollReverseHorizontal],
            ignoredDevices: Set(Defaults[.mouseScrollIgnoredDevices])
        )
    }
}

// MARK: - Events (pure)

enum ScrollEventSource: Equatable {
    case wheel
    case gesture
}

enum ScrollEventClassifier {
    /// Trackpads and the Magic Mouse send events with a scroll or momentum phase. A wheel (even a smooth-scrolling one) never does.
    static func source(isContinuous: Int64, scrollPhase: Int64, momentumPhase: Int64) -> ScrollEventSource {
        scrollPhase == 0 && momentumPhase == 0 ? .wheel : .gesture
    }

    static func source(of event: CGEvent) -> ScrollEventSource {
        source(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase)
        )
    }
}

enum ScrollReversal {
    /// Returns true when the event changed. Leaves non-scroll events and gesture events alone.
    /// The vertical axis is always flipped; the horizontal one only when `reverseHorizontal`.
    @discardableResult
    static func apply(to event: CGEvent, reverseHorizontal: Bool) -> Bool {
        guard event.type == .scrollWheel, ScrollEventClassifier.source(of: event) == .wheel else { return false }

        // Setting a delta makes CoreGraphics recompute the point delta, so read everything first and write in this order.
        let delta1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let delta2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let point1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let point2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let fixed1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let fixed2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: -delta1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: -point1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: -fixed1)

        if reverseHorizontal {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -delta2)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -point2)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -fixed2)
        }
        return true
    }
}

// MARK: - Policy (pure)

enum MouseScrollStatus: Equatable {
    case off
    case needsAccessibility
    case waitingForMouse
    case reversing
    case tapFailed

    var title: String {
        switch self {
        case .off: return "Off"
        case .needsAccessibility: return "Needs Accessibility"
        case .waitingForMouse: return "Waiting for a mouse"
        case .reversing: return "Reversing the mouse wheel"
        case .tapFailed: return "Couldn't start. Turn it off and on again."
        }
    }
}

enum MouseScrollPolicy {
    static func shouldReverse(mode: MouseScrollMode, mouseConnected: Bool) -> Bool {
        switch mode {
        case .off: return false
        case .automatic: return mouseConnected
        case .always: return true
        }
    }

    static func status(mode: MouseScrollMode, mouseConnected: Bool, accessibilityGranted: Bool, tapRunning: Bool) -> MouseScrollStatus {
        guard mode != .off else { return .off }
        guard accessibilityGranted else { return .needsAccessibility }
        guard shouldReverse(mode: mode, mouseConnected: mouseConnected) else { return .waitingForMouse }
        return tapRunning ? .reversing : .tapFailed
    }
}

enum MouseScrollDirection {
    /// The direction the wheel ends up scrolling: natural XOR reversed.
    static func name(natural: Bool, reversed: Bool) -> String {
        natural != reversed ? "Natural" : "Standard"
    }
}

enum NaturalScrolling {
    static let key = "com.apple.swipescrolldirection"
    static let didChange = Notification.Name("SwipeScrollDirectionDidChangeNotification")

    /// A missing key means natural scrolling, the macOS default.
    static func isNatural(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return true }
        return number.boolValue
    }

    static func current() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return isNatural(CFPreferencesCopyAppValue(key as CFString, kCFPreferencesAnyApplication))
    }
}
