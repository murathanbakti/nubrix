import Foundation
import Security

struct AppSigningFacts: Equatable, Sendable {
    let satisfiesReleaseRequirement: Bool
    let hasSecureTimestamp: Bool
    let teamIdentifier: String?
}

enum AppSigningIdentity {
    static let releaseRequirement = #"anchor apple generic and identifier "dev.nubrix.app" and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "399MAAJ7QT""#

    static func currentFacts() -> AppSigningFacts? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(releaseRequirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        let satisfies = SecCodeCheckValidity(code, [], requirement) == errSecSuccess
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return AppSigningFacts(
            satisfiesReleaseRequirement: satisfies,
            hasSecureTimestamp: dictionary[kSecCodeInfoTimestamp as String] is Date,
            teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String
        )
    }
}

enum UpdateBuildKind: Equatable, Sendable {
    case developerIDRelease
    case sourceBuild
    case debugBuild
    case unavailable

    static let releaseBundleIdentifier = "dev.nubrix.app"
    static let releaseTeamIdentifier = "399MAAJ7QT"
    static let feedURL = "https://github.com/murathanbakti/nubrix/releases/latest/download/appcast.xml"
    static let requiredTrueKeys = ["SUEnableInstallerLauncherService", "SUVerifyUpdateBeforeExtraction", "SURequireSignedFeed"]

    static func resolve(isDebugBuild: Bool, bundleIdentifier: String?, signing: AppSigningFacts?, info: [String: Any]) -> UpdateBuildKind {
        if isDebugBuild { return .debugBuild }
        guard bundleIdentifier == releaseBundleIdentifier else { return .sourceBuild }
        guard let signing,
              signing.satisfiesReleaseRequirement,
              signing.hasSecureTimestamp,
              signing.teamIdentifier == releaseTeamIdentifier
        else { return .sourceBuild }
        guard info["SUFeedURL"] as? String == feedURL,
              hasValidPublicKey(info),
              requiredTrueKeys.allSatisfy({ info[$0] as? Bool == true })
        else { return .unavailable }
        return .developerIDRelease
    }

    static func hasValidPublicKey(_ info: [String: Any]) -> Bool {
        guard let key = info["SUPublicEDKey"] as? String, let data = Data(base64Encoded: key) else { return false }
        return data.count == 32
    }

    static let current: UpdateBuildKind = {
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        return resolve(
            isDebugBuild: isDebug,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            signing: AppSigningIdentity.currentFacts(),
            info: Bundle.main.infoDictionary ?? [:]
        )
    }()

    var updatesEnabled: Bool { self == .developerIDRelease }

    var message: String? {
        switch self {
        case .developerIDRelease: return nil
        case .sourceBuild: return "Built from source, so Nubrix does not update itself. In your checkout:"
        case .debugBuild: return "Debug build: updates are off."
        case .unavailable: return "Updates are not available in this build."
        }
    }

    var sourceCommand: String? {
        self == .sourceBuild ? "git pull && scripts/install-local.sh" : nil
    }
}
