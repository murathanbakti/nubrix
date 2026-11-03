import AppKit
import Darwin

struct DockBadgeReadResult: Equatable {
    var running: Set<String>
    var labels: [String: String]
}

protocol DockBadgeReading: AnyObject {
    var isAvailable: Bool { get }
    func read(bundleIDs: [String]) -> DockBadgeReadResult
    func runningRegularApps() -> [String]
}

final class LaunchServicesDockBadgeReader: DockBadgeReading {
    private typealias CreateASN = @convention(c) (CFAllocator?, pid_t) -> Unmanaged<CFTypeRef>?
    private typealias CopyItem = @convention(c) (Int32, CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?

    private static let frameworkPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices"
    private static let session: Int32 = -2
    private static let key = "StatusLabel" as CFString
    private static let labelKey = "label" as CFString

    private let createASN: CreateASN?
    private let copyItem: CopyItem?

    init() {
        let handle = dlopen(Self.frameworkPath, RTLD_LAZY)
            ?? dlopen(nil, RTLD_LAZY)
            ?? UnsafeMutableRawPointer(bitPattern: -2)
        if let handle, let create = dlsym(handle, "_LSASNCreateWithPid"), let copy = dlsym(handle, "_LSCopyApplicationInformationItem") {
            createASN = unsafeBitCast(create, to: CreateASN.self)
            copyItem = unsafeBitCast(copy, to: CopyItem.self)
        } else {
            createASN = nil
            copyItem = nil
        }
    }

    var isAvailable: Bool { createASN != nil && copyItem != nil }

    func label(forPID pid: pid_t) -> String? {
        guard let createASN, let copyItem else { return nil }
        guard let asn = createASN(kCFAllocatorDefault, pid)?.takeRetainedValue() else { return nil }
        guard let value = copyItem(Self.session, asn, Self.key)?.takeRetainedValue() else { return nil }
        let type = CFGetTypeID(value)
        if type == CFDictionaryGetTypeID() {
            let dictionary = unsafeBitCast(value, to: CFDictionary.self)
            guard let entry = CFDictionaryGetValue(dictionary, Unmanaged.passUnretained(Self.labelKey).toOpaque()) else { return nil }
            let object = Unmanaged<CFTypeRef>.fromOpaque(entry).takeUnretainedValue()
            guard CFGetTypeID(object) == CFStringGetTypeID() else { return nil }
            return unsafeBitCast(object, to: CFString.self) as String
        }
        if type == CFStringGetTypeID() {
            return unsafeBitCast(value, to: CFString.self) as String
        }
        return nil
    }

    func read(bundleIDs: [String]) -> DockBadgeReadResult {
        var result = DockBadgeReadResult(running: [], labels: [:])
        var seen = Set<String>()
        for bundleID in bundleIDs where seen.insert(bundleID).inserted {
            let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
            guard !instances.isEmpty else { continue }
            result.running.insert(bundleID)
            guard isAvailable else { continue }
            for instance in instances {
                if let label = label(forPID: instance.processIdentifier) {
                    result.labels[bundleID] = label
                    break
                }
            }
        }
        return result
    }

    func runningRegularApps() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let id = app.bundleIdentifier, seen.insert(id).inserted { result.append(id) }
        }
        return result
    }
}
