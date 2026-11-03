import Foundation

enum UpdateFailure: Error, Equatable, Sendable {
    case network
    case http(Int)
    case rateLimited
    case notFound
    case redirected
    case malformed
    case invalidTag
    case notEligible
    case unknownCurrentVersion

    var message: String {
        switch self {
        case .network: "No connection to GitHub."
        case .http(let code): "GitHub answered with status \(code)."
        case .rateLimited: "GitHub rate limit reached. Try again later."
        case .notFound: "No release has been published yet."
        case .redirected: "GitHub redirected the request."
        case .malformed: "GitHub sent an unexpected answer."
        case .invalidTag: "The latest release has an unexpected version."
        case .notEligible: "The latest release is not a final release."
        case .unknownCurrentVersion: "This build has no recognizable version."
        }
    }
}

enum UpdateParsing {
    static let maxBodyBytes = 1_048_576

    private struct Payload: Decodable {
        let tag_name: String
        let draft: Bool?
        let prerelease: Bool?
    }

    static func latestVersion(from data: Data) throws -> ReleaseVersion {
        guard data.count <= maxBodyBytes else { throw UpdateFailure.malformed }
        let payload: Payload
        do { payload = try JSONDecoder().decode(Payload.self, from: data) } catch { throw UpdateFailure.malformed }
        if payload.draft == true || payload.prerelease == true { throw UpdateFailure.notEligible }
        guard let version = ReleaseVersion(tag: payload.tag_name) else { throw UpdateFailure.invalidTag }
        return version
    }
}

enum UpdateVerdict: Equatable, Sendable {
    case upToDate
    case available(ReleaseVersion)
    case skipped(ReleaseVersion)
}

enum UpdateDecision {
    static func evaluate(latest: ReleaseVersion, current: ReleaseVersion, skipped: String?) -> UpdateVerdict {
        guard latest > current else { return .upToDate }
        if skipped == latest.tag { return .skipped(latest) }
        return .available(latest)
    }
}

enum UpdateSchedule {
    static let clockSkewTolerance: TimeInterval = 300

    static func isDue(autoCheck: Bool?, lastSuccess: Date?, lastAttempt: Date?, now: Date,
                      interval: TimeInterval = 86_400, retryAfterFailure: TimeInterval = 3_600) -> Bool {
        guard autoCheck == true else { return false }
        if let lastAttempt {
            let sinceAttempt = now.timeIntervalSince(lastAttempt)
            if sinceAttempt >= 0, sinceAttempt < retryAfterFailure { return false }
        }
        guard let lastSuccess else { return true }
        if lastSuccess > now.addingTimeInterval(clockSkewTolerance) { return true }
        return now.timeIntervalSince(lastSuccess) >= interval
    }
}
