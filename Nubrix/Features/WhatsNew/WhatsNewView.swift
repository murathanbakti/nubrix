import SwiftUI

struct WhatsNewView: View {
    let notes: WhatsNewNotes
    let onAction: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(Color.effectiveAccent)
                .padding(.bottom, 10)
            Text(notes.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(notes.items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 22))
                            .foregroundStyle(Color.effectiveAccent)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.headline)
                            Text(item.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let footer = notes.footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            }

            HStack {
                Button("Close", action: onClose)
                    .keyboardShortcut(notes.actionTab == nil ? .defaultAction : .cancelAction)
                if notes.actionTab != nil, let title = notes.actionTitle {
                    Button(title, action: onAction)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
            .padding(.top, 20)
        }
        .padding(28)
        .frame(width: 440)
    }
}
