//  BrightnessManager.swift
//  Nubrix
//
//  Created by JeanLouis on 08/22/24.

import AppKit
import Foundation

final class BrightnessManager: ObservableObject {
	static let shared = BrightnessManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var animatedBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast
	/// False when the helper cannot read or set the screen brightness (for example some external displays).
	@Published private(set) var isAvailable: Bool = true

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared
	private let writer = LatestWinsWriter()

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			let available = await client.isScreenBrightnessAvailable()
			let current = available ? await client.currentScreenBrightness() : nil
			let usable = available && current != nil
			isAvailable = usable
			if let current {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting = await client.currentScreenBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			let ok = await client.setScreenBrightness(target)
			if ok {
				publish(brightness: target, touchDate: true)
			} else {
				refresh()
			}
			NubrixCoordinator.shared.toggleSneakPeek(status: true, type: .brightness, value: CGFloat(target))
		}
	}

	/// Latest value wins: while a write is in flight only the newest value is kept.
	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		let client = client
		writer.submit(clamped, send: { await client.setScreenBrightness($0) }) { [weak self] value, ok in
			if ok { self?.publish(brightness: value, touchDate: true) } else { self?.refresh() }
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
				self.animatedBrightness = brightness
			}
		}
	}
}

// (DisplayServices helpers moved into XPC helper)

// MARK: - Keyboard Backlight Controller
final class KeyboardBacklightManager: ObservableObject {
	static let shared = KeyboardBacklightManager()

	@Published private(set) var rawBrightness: Float = 0
	@Published private(set) var lastChangeAt: Date = .distantPast
	/// False when the Mac has no keyboard backlight the helper can control.
	@Published private(set) var isAvailable: Bool = true

	private let visibleDuration: TimeInterval = 1.2
	private let client = XPCHelperClient.shared
	private let writer = LatestWinsWriter()

	private init() { refresh() }

	var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }

	func refresh() {
		Task { @MainActor in
			let available = await client.isKeyboardBrightnessAvailable()
			let current = available ? await client.currentKeyboardBrightness() : nil
			let usable = available && current != nil
			isAvailable = usable
			if let current {
				publish(brightness: current, touchDate: false)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting = await client.currentKeyboardBrightness() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			let ok = await client.setKeyboardBrightness(target)
			if ok {
				publish(brightness: target, touchDate: true)
			} else {
				refresh()
			}
			NubrixCoordinator.shared.toggleSneakPeek(
				status: true,
				type: .backlight,
				value: CGFloat(target)
			)
		}
	}

	/// Latest value wins: while a write is in flight only the newest value is kept.
	func setAbsolute(value: Float) {
		let clamped = max(0, min(1, value))
		let client = client
		writer.submit(clamped, send: { await client.setKeyboardBrightness($0) }) { [weak self] value, ok in
			if ok { self?.publish(brightness: value, touchDate: true) } else { self?.refresh() }
		}
	}

	private func publish(brightness: Float, touchDate: Bool) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness || touchDate {
				if touchDate { self.lastChangeAt = Date() }
				self.rawBrightness = brightness
			}
		}
	}
}



/// Sends values one at a time, in order, and skips values that were replaced
/// while a send was in flight. Used for sliders that write over XPC while dragging.
final class LatestWinsWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: Float?
    private var running = false

    /// Stores the value. Returns true when the caller must start the send loop.
    func enqueue(_ value: Float) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        pending = value
        if running { return false }
        running = true
        return true
    }

    /// Next value to send, or nil (and the loop stops) when nothing is waiting.
    func next() -> Float? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = pending else {
            running = false
            return nil
        }
        pending = nil
        return value
    }

    func submit(
        _ value: Float,
        send: @escaping @Sendable (Float) async -> Bool,
        done: @escaping @Sendable (Float, Bool) -> Void
    ) {
        guard enqueue(value) else { return }
        Task {
            while let next = self.next() {
                let ok = await send(next)
                done(next, ok)
            }
        }
    }
}
