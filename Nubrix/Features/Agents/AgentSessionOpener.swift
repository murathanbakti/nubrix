import AppKit

enum AgentSessionOpener {
    private static let terminalBundleID = "com.apple.Terminal"
    private static let iTermBundleID = "com.googlecode.iterm2"

    private static let termBundles: [String: String] = [
        "Apple_Terminal": terminalBundleID,
        "iTerm.app": iTermBundleID,
    ]

    static func canOpen(_ source: AgentSourceInfo) -> Bool {
        source.activationBundleID != nil || termBundles[source.terminal] != nil
    }

    @MainActor
    static func open(_ source: AgentSourceInfo) {
        let bundleID = source.activationBundleID ?? termBundles[source.terminal]

        if !source.hostSessionID.isEmpty,
           source.entrypoint == "claude-desktop" || bundleID == AgentSourceInfo.desktopBundleID,
           let url = desktopURL(sessionID: source.hostSessionID),
           NSWorkspace.shared.open(url) {
            return
        }

        if !source.tty.isEmpty, let bundleID, let script = tabScript(bundleID: bundleID, tty: source.tty),
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            Task {
                let found = (try? await AppleScriptHelper.execute(script))?.booleanValue ?? false
                if !found { AgentAppActivator.activate(bundleID: bundleID) }
            }
            return
        }

        AgentAppActivator.activate(bundleID: bundleID)
    }

    private static func desktopURL(sessionID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "claude"
        components.host = "code"
        components.path = "/continue"
        components.queryItems = [URLQueryItem(name: "session", value: sessionID)]
        return components.url
    }

    private static func tabScript(bundleID: String, tty: String) -> String? {
        guard tty.wholeMatch(of: /ttys[0-9]{1,4}/) != nil else { return nil }
        let device = "/dev/\(tty)"
        switch bundleID {
        case terminalBundleID:
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
        case iTermBundleID:
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
        default:
            return nil
        }
    }
}
