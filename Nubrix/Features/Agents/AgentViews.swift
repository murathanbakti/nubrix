import AppKit
import Defaults
import SwiftUI

struct AgentLiveActivity: View {
    @EnvironmentObject var vm: NubrixViewModel
    @ObservedObject var agents = AgentSessionStore.shared

    var body: some View {
        let side = max(0, vm.effectiveClosedNotchHeight - 12)
        let state: AgentSessionState = agents.needsAttention ? .needsAttention : .working
        HStack {
            AgentStatusGlyph(state: state, size: side * 0.8)
                .frame(width: side, height: side)
            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
            Text("\(agents.activeCount)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(state.tint)
                .frame(width: side, height: side)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct AgentBannerView: View {
    @EnvironmentObject var vm: NubrixViewModel
    let banner: AgentBanner

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                AgentStatusGlyph(state: banner.state, size: 14)
                Text(banner.project)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 220, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(banner.note ?? banner.state.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(banner.state.tint)
                .lineLimit(1)
                .frame(width: 90, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct AgentPermissionHeader: View {
    @EnvironmentObject var vm: NubrixViewModel
    @ObservedObject var agents = AgentSessionStore.shared
    let prompt: AgentPermissionPrompt
    let total: Int

    var body: some View {
        let session = agents.session(prompt.payload.sessionID)
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                AgentStatusGlyph(state: .needsAttention, size: 14)
                Text(session?.projectWithBranch ?? AgentPermissionPromptView.project(for: prompt.payload))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 220, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            Text(total > 1 ? "Approve? 1 of \(total)" : "Approve?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AgentSessionState.needsAttention.tint)
                .lineLimit(1)
                .frame(width: 110, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct AgentPermissionPromptView: View {
    @ObservedObject var agents = AgentSessionStore.shared
    @ObservedObject var permissions = AgentPermissionStore.shared
    let prompt: AgentPermissionPrompt
    var position = 1
    var showsTitle = true

    static func project(for payload: AgentPermissionPayload) -> String {
        let name = URL(fileURLWithPath: payload.cwd ?? "").lastPathComponent
        return name.isEmpty || name == "/" ? "Claude" : name
    }

    var body: some View {
        let session = agents.session(prompt.payload.sessionID)
        let source = prompt.payload.source.isEmpty ? (session?.source ?? prompt.payload.source) : prompt.payload.source
        let shown = AgentPermissionPrompt(payload: Self.with(source: source, payload: prompt.payload), createdAt: prompt.createdAt)
        AgentPermissionCard(
            prompt: shown,
            title: session?.projectWithBranch ?? Self.project(for: prompt.payload),
            position: position,
            total: permissions.queue.count,
            sourceName: source.label.map { $0.replacingOccurrences(of: "Terminal · ", with: "") },
            showsTitle: showsTitle,
            onAllow: { permissions.allow(prompt.id) },
            onDeny: { permissions.deny(prompt.id) },
            onOpen: { permissions.openInSourceApp(prompt.id) }
        )
        .id(prompt.id)
    }

    static func with(source: AgentSourceInfo, payload: AgentPermissionPayload) -> AgentPermissionPayload {
        var copy = payload
        copy.source = source
        return copy
    }
}

struct AgentInfoPanelContainer: View {
    @ObservedObject var agents = AgentSessionStore.shared
    @Default(.claudeNotchApprovals) var approvals

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            AgentInfoPanel(
                snapshot: AgentInfoSnapshot(
                    lastHookEventAt: agents.lastHookEventAt,
                    lastStatusAt: agents.lastStatusAt,
                    approvalsEnabled: approvals,
                    lastPermissionRequestAt: agents.lastPermissionRequestAt,
                    sealedScripts: AgentInfoModel.sealedCount(in: AgentEventServer.configDirectory.appendingPathComponent("bin", isDirectory: true)),
                    sealedTotal: AgentInfoModel.sealedNames.count,
                    serverPort: agents.serverPort
                ),
                now: context.date,
                onCopy: {
                    let bin = AgentEventServer.configDirectory.appendingPathComponent("bin", isDirectory: true).path
                    ClipStore.shared.copyTransformed(AgentInfoModel.setupSnippet(binDirectory: bin))
                }
            )
        }
    }
}

struct AgentSessionsView: View {
    @ObservedObject var agents = AgentSessionStore.shared
    @ObservedObject var permissions = AgentPermissionStore.shared

    @State private var showsInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AgentUsageHeader(
                limits: agents.rateLimits,
                clearVisible: !showsInfo && agents.sessions.contains(where: { [.done, .failed, .idle].contains($0.state) }),
                infoActive: showsInfo,
                onInfo: { withAnimation(.smooth(duration: 0.2)) { showsInfo.toggle() } },
                onClear: { withAnimation(.smooth) { agents.clearFinished() } }
            )
            if showsInfo {
                AgentInfoPanelContainer()
            } else if agents.sessions.isEmpty && permissions.queue.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(permissions.queue.enumerated()), id: \.element.id) { index, prompt in
                            AgentPermissionPromptView(prompt: prompt, position: index + 1)
                        }
                        ForEach(agents.sortedSessions) { session in
                            AgentSessionRow(session: session)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.title2)
                .foregroundStyle(AgentSessionState.working.tint)
            Text("No Claude Code sessions")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Install the Nubrix hooks to see sessions here.")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentSessionRow: View {
    let session: AgentSession
    @ObservedObject var agents = AgentSessionStore.shared
    @State private var hovering = false

    var body: some View {
        AgentSessionRowBody(
            session: session,
            hovering: hovering,
            onRemove: { withAnimation(.smooth) { agents.remove(session.id) } }
        )
        .onHover { hovering = $0 }
        .onTapGesture { AgentAppActivator.activate(bundleID: session.source.activationBundleID) }
        .help(session.cwd)
    }
}
