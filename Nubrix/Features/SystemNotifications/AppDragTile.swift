import AppKit
import SwiftUI

struct AppDragTile: View {
    let help: String

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
            Text("Nubrix")
                .font(.caption.weight(.medium))
            Text("Drag me")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
        .onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
        .help(help)
    }
}
