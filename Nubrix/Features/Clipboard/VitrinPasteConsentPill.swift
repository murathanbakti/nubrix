import SwiftUI

struct VitrinPasteConsentPill: View {
    @ObservedObject var monitor = ClipboardMonitor.shared

    var body: some View {
        if monitor.needsPasteConsent {
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text("macOS asks before Nubrix reads copied items.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button("Save Copied Item") { monitor.captureNowByUser() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                Button("Allow in Settings…") { Permissions.client.openSystemSettings(.pasteboard) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(Color.accentColor.opacity(0.35)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 0.5))
            .padding(.horizontal, 6)
        }
    }
}
