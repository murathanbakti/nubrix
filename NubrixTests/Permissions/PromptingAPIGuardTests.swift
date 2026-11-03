import XCTest

final class PromptingAPIGuardTests: XCTestCase {
    private static let tokens = [
        "requestFullAccessTo",
        "requestAccess(for:",
        "kAXTrustedCheckOptionPrompt",
        "NSAppleScript(",
        "CGRequest",
        "requestAuthorization(",
        "promptIfNeeded: true",
        ".requestAccessibilityAuthorization()",
        "AEDeterminePermissionToAutomateTarget"
    ]

    private static let allowlist: Set<String> = [
        "Nubrix/Features/Permissions/PermissionClient.swift",
        "Nubrix/helpers/AppleScriptHelper.swift",
        "Nubrix/XPCHelperClient/XPCHelperClient.swift"
    ]

    func testRequestingAPIsStayBehindThePermissionClient() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { root.deleteLastPathComponent() }
        let source = root.appendingPathComponent("Nubrix", isDirectory: true)

        guard FileManager.default.isReadableFile(atPath: source.path),
              let enumerator = FileManager.default.enumerator(
                at: source,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              )
        else {
            throw XCTSkip("Sources not readable from the test host sandbox: \(source.path)")
        }

        var scanned = 0
        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let relative = String(url.path.dropFirst(root.path.count + 1))
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw XCTSkip("Cannot read \(relative) from the test host sandbox")
            }
            scanned += 1
            if Self.allowlist.contains(relative) { continue }
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                for token in Self.tokens where line.contains(token) {
                    violations.append("\(relative):\(index + 1): \(token)")
                }
            }
        }

        XCTAssertGreaterThan(scanned, 50, "Scanned too few files under \(source.path)")
        XCTAssertTrue(violations.isEmpty, "Prompting APIs outside the allowlist:\n" + violations.joined(separator: "\n"))
    }
}
