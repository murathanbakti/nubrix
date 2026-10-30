import SwiftUI

struct AgentStatusGlyph: View {
    let state: AgentSessionState
    var size: CGFloat = 14
    @State private var spin = false

    var body: some View {
        Group {
            switch state {
            case .working:
                Circle()
                    .trim(from: 0.15, to: 0.85)
                    .stroke(state.tint, style: StrokeStyle(lineWidth: max(1.5, size / 7), lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
                    .padding(size * 0.08)
            case .needsAttention:
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .foregroundStyle(state.tint)
                    .symbolEffect(.pulse, options: .repeating)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .foregroundStyle(state.tint)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .foregroundStyle(state.tint)
            case .idle:
                Image(systemName: "moon.zzz.fill")
                    .resizable()
                    .foregroundStyle(state.tint)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: size, height: size)
    }
}

struct AgentLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
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
    @EnvironmentObject var vm: BoringViewModel
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

            Text(banner.state.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(banner.state.tint)
                .lineLimit(1)
                .frame(width: 90, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct AgentSessionsView: View {
    @ObservedObject var agents = AgentSessionStore.shared

    var body: some View {
        Group {
            if agents.sessions.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    header
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 4) {
                            ForEach(agents.sortedSessions) { session in
                                AgentSessionRow(session: session)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 4)
    }

    private var header: some View {
        HStack {
            Text("Claude Code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.gray)
            Spacer()
            if agents.sessions.contains(where: { [.done, .failed, .idle].contains($0.state) }) {
                Button("Clear finished") { withAnimation(.smooth) { agents.clearFinished() } }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.horizontal, 4)
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
        HStack(spacing: 10) {
            AgentStatusGlyph(state: session.state, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.project)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(session.state.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(session.state.tint)
                }
                if let detail = session.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            if hovering && session.state != .working && session.state != .needsAttention {
                Button {
                    withAnimation(.smooth) { agents.remove(session.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(Self.age(from: session.updatedAt, to: context.date))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hovering ? 0.1 : 0.06)))
        .onHover { hovering = $0 }
        .help(session.cwd)
    }

    private static func age(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
