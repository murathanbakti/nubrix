import AppKit
import SwiftUI

enum DevSection: String, CaseIterable, Identifiable {
    case github = "GitHub"
    case servers = "Servers"
    case notifications = "Notifications"

    var id: String { rawValue }
}

@MainActor
final class DevTabNavigation: ObservableObject {
    static let shared = DevTabNavigation()
    @Published var requested: DevSection?
    private init() {}
}

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var requested: String?
    private init() {}

    func open(_ tab: String) {
        requested = tab
        SettingsWindowController.shared.showWindow()
    }
}

enum GitHubFormat {
    static let blue = Color(red: 0.35, green: 0.65, blue: 1.0)

    static func age(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }

    static func shortRepo(_ repo: String) -> String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }

    static func time(_ date: Date) -> String {
        AgentMeter.resetTime(date)
    }
}

struct GitHubCheckGlyph: View {
    let state: GitHubCheckState
    var size: CGFloat = 12

    var body: some View {
        Group {
            switch state {
            case .success:
                Image(systemName: "checkmark.circle.fill").resizable().foregroundStyle(Color.green)
            case .failure:
                Image(systemName: "xmark.circle.fill").resizable().foregroundStyle(Color.red)
            case .pending:
                Image(systemName: "circle.fill").resizable().foregroundStyle(Color.orange).padding(size * 0.2)
            case .none:
                Image(systemName: "circle.dotted").resizable().foregroundStyle(Color.gray)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
    }
}

struct GitHubRunGlyph: View {
    let state: GitHubRunState
    var size: CGFloat = 12

    var body: some View {
        Group {
            switch state {
            case .running:
                AgentAnimatedGlyph(mode: .spinner, color: .orange)
            case .success:
                Image(systemName: "checkmark.circle.fill").resizable().foregroundStyle(Color.green)
            case .failure:
                Image(systemName: "xmark.circle.fill").resizable().foregroundStyle(Color.red)
            case .cancelled:
                Image(systemName: "slash.circle.fill").resizable().foregroundStyle(Color.gray)
            case .neutral:
                Image(systemName: "minus.circle.fill").resizable().foregroundStyle(Color.gray)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
    }
}

struct GitHubBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.18)))
            .fixedSize()
    }
}

struct GitHubPRChip: View {
    let pr: GitHubPR

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            HStack(spacing: 3) {
                Text("#\(pr.number)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(white: 0.78))
                GitHubCheckGlyph(state: pr.checks, size: 10)
                if pr.merge == .conflicting {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.orange)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.09)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("\(pr.title)\n\(pr.reference)")
    }
}

struct GitHubPRRow: View {
    let pr: GitHubPR
    let now: Date
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
        } label: {
            HStack(spacing: 6) {
                GitHubCheckGlyph(state: pr.checks, size: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(GitHubFormat.shortRepo(pr.repo)) #\(pr.number) · \(GitHubFormat.age(from: pr.updatedAt, to: now))")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 2)
                HStack(spacing: 3) {
                    if pr.isDraft { GitHubBadge(text: "draft", tint: .gray) }
                    switch pr.review {
                    case .approved: GitHubBadge(text: "\u{2713}", tint: .green)
                    case .changesRequested: GitHubBadge(text: "\u{0394}", tint: .orange)
                    default: EmptyView()
                    }
                    if pr.merge == .conflicting {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(pr.title)\n\(pr.reference) by \(pr.author)")
    }
}

struct GitHubRunRow: View {
    let run: GitHubRun
    let now: Date
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(run.url)
        } label: {
            HStack(spacing: 6) {
                GitHubRunGlyph(state: run.state, size: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("\(GitHubFormat.shortRepo(run.repo)) · \(run.branch) · \(GitHubFormat.age(from: run.updatedAt, to: now))")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(run.title)\n\(run.repo) · \(run.event)")
    }
}

struct GitHubSection: View {
    @ObservedObject var store: GitHubStore
    var onOpenSettings: () -> Void = { SettingsNavigation.shared.open("GitHub") }

    var body: some View {
        switch store.connection {
        case .noToken:
            prompt(icon: "arrow.triangle.branch", title: "Connect GitHub",
                   detail: "Pull requests, reviews and Actions runs from a read-only token.", button: "Connect GitHub")
        case .unauthorized:
            prompt(icon: "key.slash", title: "GitHub rejected the token",
                   detail: "It may have expired or been revoked.", button: "Open GitHub settings")
        case .connecting where store.lastRefresh == nil:
            VStack {
                Text("Loading GitHub")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            columns
        }
    }

    private var columns: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(alignment: .top, spacing: 8) {
                column("Review requested", count: store.reviewRequests.count) {
                    ForEach(store.reviewRequests) { GitHubPRRow(pr: $0, now: context.date) }
                } empty: { "No review requests" }
                column("My PRs", count: store.myPRs.count) {
                    ForEach(store.myPRs) { GitHubPRRow(pr: $0, now: context.date) }
                } empty: { "No open PRs" }
                column("Actions", count: store.runs.count) {
                    ForEach(store.runs) { GitHubRunRow(run: $0, now: context.date) }
                } empty: { "No recent runs" }
            }
        }
    }

    private func column<Rows: View>(_ title: String, count: Int, @ViewBuilder rows: () -> Rows,
                                    empty: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.gray)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color(white: 0.45))
                }
            }
            .padding(.horizontal, 2)
            if count == 0 {
                Text(empty())
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) { rows() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func prompt(icon: String, title: String, detail: String, button: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.gray)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.gray)
            Button(action: onOpenSettings) {
                Text(button)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DevSectionBar: View {
    @Binding var selection: DevSection
    @ObservedObject var github: GitHubStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DevSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Text(section.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selection == section ? Color.white : Color.gray)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(selection == section ? 0.14 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if selection == .github, github.hasToken {
                statusText
                Button {
                    github.refreshNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
                .help("Refresh now")
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var statusText: some View {
        switch github.connection {
        case .rateLimited(let until):
            Text("Rate limited until \(GitHubFormat.time(until))")
                .font(.system(size: 10))
                .foregroundStyle(Color.orange)
        case .failing(let message):
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(Color.orange)
        case .unauthorized:
            Text("Token rejected")
                .font(.system(size: 10))
                .foregroundStyle(Color.red)
        default:
            if !github.login.isEmpty {
                Text("@\(github.login)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
    }
}
