import Foundation
import Security

enum AppSigningIdentity {
    static func teamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              team.count == 10,
              team.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
        else { return nil }
        return team
    }
}

enum UpdateLinks {
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/murathanbakti/nubrix/releases/latest")!

    static func releaseURL(for version: ReleaseVersion) -> URL {
        URL(string: "https://github.com/murathanbakti/nubrix/releases/tag/\(version.tag)")!
    }
}

struct UpdateInstructions: Equatable, Sendable {
    let summary: String
    let command: String
    let showsViewRelease: Bool
    let hooksReminder: String
}

enum UpdateInstallKind: Equatable, Sendable {
    case homebrew
    case releaseZip
    case sourceBuild

    static let releaseTeamIdentifier = "399MAAJ7QT"

    static func resolve(teamIdentifier: String?, isHomebrew: Bool) -> UpdateInstallKind {
        guard teamIdentifier == releaseTeamIdentifier else { return .sourceBuild }
        return isHomebrew ? .homebrew : .releaseZip
    }

    var instructions: UpdateInstructions {
        switch self {
        case .homebrew:
            UpdateInstructions(
                summary: "Installed with Homebrew. Update in Terminal:",
                command: "brew upgrade --cask nubrix",
                showsViewRelease: true,
                hooksReminder: Self.releaseHooksReminder
            )
        case .releaseZip:
            UpdateInstructions(
                summary: "Download it from the release page, or run the install script again:",
                command: "curl -fsSL https://raw.githubusercontent.com/murathanbakti/nubrix/main/scripts/install.sh | bash",
                showsViewRelease: true,
                hooksReminder: Self.releaseHooksReminder
            )
        case .sourceBuild:
            UpdateInstructions(
                summary: "Built from source. In your checkout:",
                command: "git pull && scripts/install-local.sh",
                showsViewRelease: true,
                hooksReminder: "install-local.sh already runs install-hooks.sh, so the sealed hook copies match the new version. Reopen Nubrix afterwards."
            )
        }
    }

    private static let releaseHooksReminder = "After updating, run install-hooks.sh again so the sealed hook copies match the new version, then reopen Nubrix: bash /Applications/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh"
}
