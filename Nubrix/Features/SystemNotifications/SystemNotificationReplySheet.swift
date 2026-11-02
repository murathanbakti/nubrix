import AppKit
import SwiftUI

enum SystemNotificationReplyMetrics {
    static let contentSize = CGSize(width: 380, height: 78)
    static let bottomInset: CGFloat = 16
    static let sideInset: CGFloat = 16

    static func sheetSize(notchHeight: CGFloat) -> CGSize {
        CGSize(
            width: contentSize.width + (NotchExtensionMetrics.attachedTopRadius + sideInset) * 2,
            height: notchHeight + contentSize.height + bottomInset
        )
    }
}

@MainActor
enum SystemNotificationReplySheet {
    static let extensionID = "dev.nubrix.notificationReply"

    static func present(record: SystemNotificationRecord, screenUUID: String? = nil) {
        let host = NotchExtensionHost.shared
        if host.isPresenting(extensionID) { host.dismiss(id: extensionID, animated: false) }
        let notchHeight = getClosedNotchSize(screenUUID: screenUUID ?? NubrixCoordinator.shared.selectedScreenUUID).height
        host.present(
            id: extensionID,
            mode: .attached(size: SystemNotificationReplyMetrics.sheetSize(notchHeight: notchHeight)),
            screenUUID: screenUUID,
            activatesOnPresent: true,
            content: { SystemNotificationReplyContent(record: record) }
        )
    }

    static func dismiss(animated: Bool = true) {
        NotchExtensionHost.shared.dismiss(id: extensionID, animated: animated)
    }
}

struct SystemNotificationReplyContent: View {
    let record: SystemNotificationRecord
    @ObservedObject var store = SystemNotificationStore.shared
    @Environment(\.notchExtensionDismiss) private var dismiss
    @State private var text = ""
    @State private var phase: Phase = .idle
    @State private var access: Bool?
    @FocusState private var focused: Bool

    private enum Phase: Equatable {
        case idle
        case sending
        case sent
        case note(String)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { phase == .idle && access == true && !trimmed.isEmpty }
    private var target: String { record.title.isEmpty ? record.appName : record.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                icon
                    .frame(width: 16, height: 16)
                Text("Reply to \(target)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
            if access == false {
                HStack(spacing: 8) {
                    Text("Replying from the notch needs Accessibility.")
                        .font(.system(size: 12))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Button("Allow…") {
                        AccessibilityGuide.begin(resume: record)
                        dismiss()
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 8) {
                    TextField("Reply to \(target)", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focused)
                        .disabled(phase != .idle || access == nil)
                        .onSubmit(send)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                    trailing
                }
                statusLine
                    .frame(height: 14, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, SystemNotificationReplyMetrics.sideInset)
        .padding(.top, 4)
        .task {
            access = await XPCHelperClient.shared.isAccessibilityAuthorized()
            guard access == true else { return }
            try? await Task.sleep(for: .milliseconds(250))
            focused = true
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch phase {
        case .sending:
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 22)
        case .sent:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.green)
                .frame(width: 22, height: 22)
        default:
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(canSend ? Color.white : Color.gray)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .frame(width: 22, height: 22)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch phase {
        case .sent:
            Text("Sent")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .note(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.gray)
                .lineLimit(1)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = store.icon(for: record.bundleID) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "app.badge")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
    }

    private func send() {
        guard canSend else { return }
        let message = trimmed
        phase = .sending
        Task {
            let status = await store.reply(to: record, text: message)
            switch status {
            case .sent:
                phase = .sent
                try? await Task.sleep(for: .milliseconds(900))
                dismiss()
            case .notFound:
                await show("Couldn't find this notification in Notification Center. Text copied, paste it in \(record.appName).", status)
            case .failed:
                await show("Couldn't reply from the notch. Text copied, paste it in \(record.appName).", status)
            case .unsupported:
                await show("\(record.appName) has no reply action in its notifications. Text copied.", status)
            case .noAccess:
                await show("Nubrix needs Accessibility to reply. Text copied.", status)
            case .unconfirmed:
                await show("Reply sent, but Nubrix couldn't confirm it. Check \(record.appName).", status)
            }
        }
    }

    private func show(_ message: String, _ status: SystemNotificationReplyStatus) async {
        phase = .note(message)
        try? await Task.sleep(for: .seconds(2.5))
        dismiss()
        store.finishReply(status, record: record)
    }
}
