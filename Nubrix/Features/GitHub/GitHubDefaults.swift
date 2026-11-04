import Defaults

extension Defaults.Keys {
    static let githubEnabled = Key<Bool>("githubEnabled", default: false)
    static let githubTokenSaved = Key<Bool>("githubTokenSaved", default: false)
    static let githubLogin = Key<String>("githubLogin", default: "")
    static let githubExcludedRepos = Key<[String]>("githubExcludedRepos", default: [])
    static let githubExtraRepos = Key<[String]>("githubExtraRepos", default: [])
    static let githubNotifyReviews = Key<Bool>("githubNotifyReviews", default: true)
    static let githubNotifyCI = Key<Bool>("githubNotifyCI", default: true)
    static let githubNotifyConflicts = Key<Bool>("githubNotifyConflicts", default: true)
    static let inboxGithubEnabled = Key<Bool>("inboxGithubEnabled", default: true)
}
