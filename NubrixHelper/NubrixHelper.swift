//
//  NubrixHelper.swift
//  NubrixHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics

class NubrixHelper: NSObject, NubrixHelperProtocol {
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")
        private let fadeSetSelector = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")
        private let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil && currentBrightness() != nil }

        /// First keyboard backlight id from `copyKeyboardBacklightIDs`, else 1.
        private var keyboardID: UInt64 {
            guard let clientInstance, clientInstance.responds(to: idsSelector),
                  let result = clientInstance.perform(idsSelector)?.takeRetainedValue() as? NSArray,
                  let first = (result.firstObject as? NSNumber)?.uint64Value
            else { return 1 }
            return first
        }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            let value = fn(clientInstance, getSelector, keyboardID)
            return value.isFinite && value >= 0 && value <= 1 ? value : nil
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance else { return false }
            let id = keyboardID
            // Commit with no fade, so auto-adjust does not undo the change.
            if let fn: FadeBrightnessSetter = methodIMP(on: clientInstance, selector: fadeSetSelector, as: FadeBrightnessSetter.self) {
                return fn(clientInstance, fadeSetSelector, value, 0, ObjCBool(true), id).boolValue
            }
            guard let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, id).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool
        private typealias FadeBrightnessSetter = @convention(c) (NSObject, Selector, Float, Int32, ObjCBool, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(max(0, min(1, value))))
    }

    // MARK: - Screen Brightness (moved from client app into helper)

    /// Display to control: the main display if DisplayServices can read it, else the
    /// built-in display. `nil` means use the IOKit path on the main display.
    private func brightnessDisplayID() -> CGDirectDisplayID? {
        var probe: Float = 0
        let main = CGMainDisplayID()
        if displayServicesGetBrightness(displayID: main, out: &probe) { return main }

        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        for id in ids.prefix(Int(count)) where CGDisplayIsBuiltin(id) != 0 {
            if displayServicesGetBrightness(displayID: id, out: &probe) { return id }
        }
        return nil
    }

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(brightnessDisplayID() != nil || ioServiceFor(displayID: CGMainDisplayID()).map { IOObjectRelease($0); return true } ?? false)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if let id = brightnessDisplayID(), displayServicesGetBrightness(displayID: id, out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            let ok = IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess
            IOObjectRelease(io)
            if ok {
                reply(NSNumber(value: level))
                return
            }
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if let id = brightnessDisplayID(), displayServicesSetBrightness(displayID: id, value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    @objc func fetchClaudePlanUsage(with reply: @escaping (Data) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            reply(ClaudePlanUsageProbe.fetch().encoded())
        }
    }

    private let systemNotificationReader = SystemNotificationReader()
    private let systemNotificationQueue = DispatchQueue(label: "dev.nubrix.helper.systemNotifications", qos: .utility)

    @objc func fetchSystemNotifications(after cursor: Int64, allowedApps: [String], with reply: @escaping (Data) -> Void) {
        let allowed = Set(allowedApps.prefix(200).filter { !$0.isEmpty && $0.utf8.count <= 255 })
        let safeCursor = cursor < 0 ? -1 : cursor
        systemNotificationQueue.async {
            reply(self.systemNotificationReader.fetch(after: safeCursor, allowed: allowed).encoded())
        }
    }

    @objc func fetchSystemNotificationApps(with reply: @escaping (Data) -> Void) {
        systemNotificationQueue.async {
            reply(self.systemNotificationReader.apps().encoded())
        }
    }

    // MARK: - Bluetooth power

    @objc func bluetoothPowerState(with reply: @escaping (NSNumber?) -> Void) {
        reply(BluetoothPowerBridge.state().map { NSNumber(value: $0) })
    }

    @objc func setBluetoothPower(_ on: Bool, with reply: @escaping (Bool) -> Void) {
        reply(BluetoothPowerBridge.set(on))
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}


/// Private IOBluetooth power functions. The first call sets up a CoreBluetooth coordinator that can
/// wait forever when macOS never answers, so every call runs on a worker with a timeout; after a
/// timeout the bridge stays "unavailable" instead of piling up blocked threads.
private enum BluetoothPowerBridge {
    private typealias GetFn = @convention(c) () -> Int32
    private typealias SetFn = @convention(c) (Int32) -> Int32

    private static let queue = DispatchQueue(label: "dev.nubrix.helper.bluetooth-power")
    private static let lock = NSLock()
    private static var stuck = false

    private static let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)

    private static func run<T>(_ work: @escaping () -> T?) -> T? {
        lock.lock()
        let blocked = stuck
        lock.unlock()
        guard !blocked else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        queue.async {
            result = work()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            lock.lock()
            stuck = true
            lock.unlock()
            return nil
        }
        return result
    }

    /// 1 on, 0 off, `nil` when unavailable.
    static func state() -> Int32? {
        run {
            guard let handle, let sym = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
            return unsafeBitCast(sym, to: GetFn.self)()
        }
    }

    static func set(_ on: Bool) -> Bool {
        run { () -> Bool? in
            guard let handle, let sym = dlsym(handle, "IOBluetoothPreferenceSetControllerPowerState") else { return nil }
            _ = unsafeBitCast(sym, to: SetFn.self)(on ? 1 : 0)
            return true
        } ?? false
    }
}
