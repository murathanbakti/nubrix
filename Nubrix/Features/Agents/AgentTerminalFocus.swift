import Carbon
import Foundation

enum AgentTerminalFocus {
    static let terminal = "com.apple.Terminal"
    static let iTerm = "com.googlecode.iterm2"
    static let ghostty = "com.mitchellh.ghostty"
    static let warpStable = "dev.warp.Warp-Stable"

    static let termBundles: [String: String] = [
        "Apple_Terminal": terminal,
        "iTerm.app": iTerm,
        "ghostty": ghostty,
        "WarpTerminal": warpStable,
    ]

    enum GhosttySupport: Equatable {
        case ttyAndDirectory
        case directoryOnly
        case none
    }

    struct Script: Equatable {
        var bundleID: String
        var source: String
        var handler: String?
        var arguments: [String]
    }

    enum Strategy: Equatable {
        case desktop(URL)
        case warp(URL)
        case script(Script)
        case activate
    }

    static func bundleID(for source: AgentSourceInfo) -> String? {
        source.activationBundleID ?? termBundles[source.terminal]
    }

    static func isWarp(bundleID: String?, terminal: String) -> Bool {
        (bundleID?.hasPrefix("dev.warp.") ?? false) || terminal == "WarpTerminal"
    }

    static func isWarpHandler(bundleID: String?) -> Bool {
        bundleID?.hasPrefix("dev.warp.") ?? false
    }

    static func ttyDevice(_ tty: String) -> String? {
        let device = "/dev/" + tty
        return device.wholeMatch(of: /\/dev\/ttys[0-9]{1,4}/) != nil ? device : nil
    }

    static func directory(_ cwd: String?) -> String? {
        guard let cwd, cwd.hasPrefix("/"), cwd.count <= 1024 else { return nil }
        guard !cwd.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        return cwd
    }

    static func ghosttySupport(version: String?) -> GhosttySupport {
        guard let version, let match = version.prefixMatch(of: /([0-9]+)(?:\.([0-9]+))?/),
              let major = Int(match.1) else { return .ttyAndDirectory }
        let minor = match.2.flatMap { Int($0) } ?? 0
        if major > 1 || (major == 1 && minor >= 4) { return .ttyAndDirectory }
        if major == 1 && minor == 3 { return .directoryOnly }
        return .none
    }

    static func desktopURL(sessionID: String) -> URL? {
        guard sessionID.wholeMatch(of: /local_[A-Za-z0-9-]{1,64}/) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: sessionID)]
        return components.url
    }

    static func strategy(source: AgentSourceInfo, cwd: String?, ghosttyVersion: String?) -> Strategy {
        let bundleID = bundleID(for: source)

        if !source.hostSessionID.isEmpty,
           source.entrypoint == "claude-desktop" || bundleID == AgentSourceInfo.desktopBundleID,
           let url = desktopURL(sessionID: source.hostSessionID) {
            return .desktop(url)
        }

        if isWarp(bundleID: bundleID, terminal: source.terminal) {
            if AgentSourceInfo.isValidFocusURL(source.focusURL), let url = URL(string: source.focusURL) { return .warp(url) }
            return .activate
        }

        switch bundleID {
        case terminal:
            guard let device = ttyDevice(source.tty), let script = terminalScript(device: device) else { return .activate }
            return .script(Script(bundleID: terminal, source: script, handler: nil, arguments: []))
        case iTerm:
            guard let device = ttyDevice(source.tty), let script = iTermScript(device: device) else { return .activate }
            return .script(Script(bundleID: iTerm, source: script, handler: nil, arguments: []))
        case ghostty:
            let support = ghosttySupport(version: ghosttyVersion)
            if support == .none { return .activate }
            let tty = support == .ttyAndDirectory ? (ttyDevice(source.tty) ?? "") : ""
            let dir = directory(cwd) ?? ""
            if tty.isEmpty && dir.isEmpty { return .activate }
            return .script(Script(bundleID: ghostty, source: ghosttySource, handler: "nubrix_focus", arguments: [tty, dir]))
        default:
            return .activate
        }
    }

    static func terminalScript(device: String) -> String? {
        guard ttyDevice(String(device.dropFirst(5))) == device else { return nil }
        return """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(device)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    static func iTermScript(device: String) -> String? {
        guard ttyDevice(String(device.dropFirst(5))) == device else { return nil }
        return """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(device)" then
                            select w
                            select t
                            select s
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    static let ghosttySource = """
    on nubrix_focus(targetTTY, targetDir)
        tell application id "com.mitchellh.ghostty"
            if targetTTY is not "" then
                try
                    repeat with t in terminals
                        if («property Gtty» of t) is targetTTY then
                            focus (contents of t)
                            activate
                            return true
                        end if
                    end repeat
                end try
            end if
            if targetDir is not "" then
                set matches to {}
                repeat with t in terminals
                    if (working directory of t) is targetDir then set end of matches to (contents of t)
                end repeat
                if (count of matches) is 1 then
                    focus (item 1 of matches)
                    activate
                    return true
                end if
            end if
        end tell
        return false
    end nubrix_focus
    """

    static func subroutineEvent(handler: String, arguments: [String]) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: NSAppleEventDescriptor.currentProcess(),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        event.setDescriptor(NSAppleEventDescriptor(string: handler.lowercased()), forKeyword: AEKeyword(keyASSubroutineName))
        let list = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            list.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }
        event.setDescriptor(list, forKeyword: AEKeyword(keyDirectObject))
        return event
    }

    static func run(_ script: Script) async throws -> Bool {
        let descriptor = try await runDescriptor(script)
        return descriptor.booleanValue
    }

    static func runDescriptor(_ script: Script) async throws -> NSAppleEventDescriptor {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                guard let appleScript = NSAppleScript(source: script.source) else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid script"]))
                    return
                }
                var error: NSDictionary?
                let descriptor: NSAppleEventDescriptor?
                if let handler = script.handler {
                    if !appleScript.compileAndReturnError(&error) {
                        continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any] ?? [NSLocalizedDescriptionKey: "Compile failed"]))
                        return
                    }
                    let event = subroutineEvent(handler: handler, arguments: script.arguments)
                    descriptor = appleScript.executeAppleEvent(event, error: &error)
                } else {
                    descriptor = appleScript.executeAndReturnError(&error)
                }
                if let descriptor {
                    continuation.resume(returning: descriptor)
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any] ?? [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }
}
