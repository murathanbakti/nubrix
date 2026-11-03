import AppKit
import Defaults

enum AgentSessionOpener {
    static var isAllowed: Bool {
        Defaults[.claudeEnabled] && Defaults[.claudeOpenSession]
    }

    static func canOpen(_ source: AgentSourceInfo) -> Bool {
        isAllowed && AgentTerminalFocus.bundleID(for: source) != nil
    }

    @MainActor
    static func open(_ source: AgentSourceInfo, cwd: String? = nil) {
        guard isAllowed else { return }
        let bundleID = AgentTerminalFocus.bundleID(for: source)

        var ghosttyVersion: String?
        if bundleID == AgentTerminalFocus.ghostty {
            ghosttyVersion = NSRunningApplication.runningApplications(withBundleIdentifier: AgentTerminalFocus.ghostty)
                .first?.bundleURL
                .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }
        }

        switch AgentTerminalFocus.strategy(source: source, cwd: cwd, ghosttyVersion: ghosttyVersion) {
        case .desktop(let url):
            if !NSWorkspace.shared.open(url) { AgentAppActivator.activate(bundleID: bundleID) }
        case .warp(let url):
            let handler = NSWorkspace.shared.urlForApplication(toOpen: url).flatMap { Bundle(url: $0)?.bundleIdentifier }
            if AgentTerminalFocus.isWarpHandler(bundleID: handler), NSWorkspace.shared.open(url) { return }
            AgentAppActivator.activate(bundleID: bundleID)
        case .script(let script):
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: script.bundleID).isEmpty else {
                AgentAppActivator.activate(bundleID: bundleID)
                return
            }
            Task {
                let found = (try? await AgentTerminalFocus.run(script)) ?? false
                if !found { AgentAppActivator.activate(bundleID: script.bundleID) }
            }
        case .activate:
            AgentAppActivator.activate(bundleID: bundleID)
        }
    }
}
