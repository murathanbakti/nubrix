import AppKit
import Defaults
import SwiftUI

struct GitHubSettings: View {
    @ObservedObject var store = GitHubStore.shared
    @Default(.githubExcludedRepos) var excluded
    @Default(.githubExtraRepos) var extras
    @Default(.githubEnabled) var enabled
    @State private var tokenText = ""
    @State private var working = false
    @State private var error: String?
    @State private var repoText = ""
    @State private var repoError = false
    @State private var rateLimit: GitHubRateLimit?

    static let tokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new")!

    static let permissions: [(String, String)] = [
        ("Metadata", "Read (added automatically)"),
        ("Pull requests", "Read"),
        ("Actions", "Read"),
        ("Commit statuses", "Read"),
        ("Checks", "Read (optional, sharper CI status)"),
    ]

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .githubEnabled) {
                    Text("Enable GitHub integration")
                }
            } footer: {
                SettingsFooter("When off, Nubrix does not read the token or contact api.github.com. The token stays in the Keychain.")
            }
            Group {
                connectionSection
                tokenHelpSection
                if store.hasToken {
                    repositoriesSection
                }
                notificationsSection
                pollingSection
            }
            .disabled(!enabled)
        }
        .settingsPage(.github)
        .task(id: store.lastRefresh) { rateLimit = await store.rateLimit() }
    }

    private var connectionSection: some View {
        Section {
            if store.hasToken {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.login.isEmpty ? "Connected" : "Connected as @\(store.login)")
                        Text(statusLine)
                            .font(.caption)
                            .foregroundStyle(store.connection == .unauthorized ? Color.red : Color.secondary)
                    }
                    Spacer()
                    Text("github_pat_\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}\u{2022}")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Button("Remove", role: .destructive) { store.disconnect() }
                }
            } else {
                SecureField("Fine-grained token", text: $tokenText)
                    .onSubmit(save)
                    .onChange(of: tokenText) { _, _ in error = nil }
                HStack {
                    Button(working ? "Checking" : "Save", action: save)
                        .disabled(working || tokenText.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        } header: {
            Text("Connection")
        } footer: {
            SettingsFooter("The token is stored in the macOS Keychain (item dev.nubrix.github) and is never written to preferences, logs or files.")
        }
    }

    private var statusLine: String {
        switch store.connection {
        case .connected: return "Token accepted"
        case .connecting: return "Checking"
        case .unauthorized: return "GitHub rejected the token. Remove it and create a new one."
        case .rateLimited(let until): return "Rate limited until \(GitHubFormat.time(until))"
        case .failing(let message): return message
        case .noToken: return ""
        case .disabled: return "Off"
        }
    }

    private var tokenHelpSection: some View {
        Section {
            Button("Create token on GitHub") { NSWorkspace.shared.open(Self.tokenURL) }
            DisclosureGroup("How to create a read-only token") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("1. Resource owner: your account (or the organization that owns the repositories).")
                    Text("2. Repository access: Only select repositories, then pick the ones you want here.")
                    Text("3. Repository permissions, all read-only:")
                    ForEach(Self.permissions, id: \.0) { item in
                        Text("\u{2022} \(item.0): \(item.1)")
                            .padding(.leading, 14)
                    }
                    Text("4. Leave everything else at No access, and choose a short expiry.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        } header: {
            Text("Token")
        } footer: {
            SettingsFooter("Nubrix never needs write access. A token can read every repository you select, so select only those you use.")
        }
    }

    private var repositoriesSection: some View {
        Section {
            if store.accessibleRepos.isEmpty {
                Text("No repositories listed yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(store.accessibleRepos) { repo in
                Toggle(isOn: Binding(
                    get: { !excluded.contains { GitHubRemote.sameRepo($0, repo.fullName) } },
                    set: { store.setRepo(repo.fullName, enabled: $0) }
                )) {
                    Text(repo.fullName)
                }
            }
            ForEach(extras, id: \.self) { name in
                HStack {
                    Text(name)
                    Text("added manually")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") { store.removeExtraRepo(name) }
                }
            }
            HStack {
                TextField("owner/repo", text: $repoText)
                    .onSubmit(addRepo)
                    .onChange(of: repoText) { _, _ in repoError = false }
                Button("Add", action: addRepo)
                    .disabled(repoText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if repoError {
                Text("Enter a repository as owner/repo.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Watched repositories")
        } footer: {
            SettingsFooter("Pull requests come from every repository the token can read. Actions runs are fetched for the repositories switched on here, your Claude sessions and your open PRs, at most \(GitHubStore.maxWatchedRepos) at a time.")
        }
    }

    private var notificationsSection: some View {
        Section {
            Defaults.Toggle(key: .githubNotifyReviews) { Text("New review requests") }
            Defaults.Toggle(key: .githubNotifyCI) { Text("CI results and failed workflow runs") }
            Defaults.Toggle(key: .githubNotifyConflicts) { Text("Merge conflicts on my PRs") }
        } header: {
            Text("Notifications")
        } footer: {
            SettingsFooter("Banners appear in the closed notch and count as unread. Failed runs are reported for default branches, your open PRs, your Claude sessions and runs you started.")
        }
        .disabled(!store.hasToken)
    }

    private var pollingSection: some View {
        Section {
            Text("Every \(Int(GitHubStore.idleInterval)) s in the background, every \(Int(GitHubStore.activeInterval)) s while the GitHub list in the notch is open or a run is in progress.")
                .foregroundStyle(.secondary)
            if let rateLimit {
                Text("Rate limit left: \(rateLimit.remaining), resets at \(GitHubFormat.time(rateLimit.resetAt)).")
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("More about polling") {
                Text("Paused while the Mac sleeps or is locked, and when no token is saved. Actions requests use ETags, so unchanged answers (304) do not use rate limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        } header: {
            Text("Polling")
        }
    }

    private func save() {
        guard !working else { return }
        working = true
        let candidate = tokenText
        Task {
            let result = await store.connect(token: candidate)
            working = false
            if let result {
                error = result
            } else {
                tokenText = ""
                error = nil
            }
        }
    }

    private func addRepo() {
        if store.addRepo(repoText) {
            repoText = ""
            repoError = false
        } else {
            repoError = true
        }
    }
}
