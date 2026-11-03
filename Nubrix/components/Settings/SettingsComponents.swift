import AppKit
import SwiftUI

struct SettingsFooter: View {
    let text: String
    var link: (title: String, url: URL)?

    init(_ text: String, link: (title: String, url: URL)? = nil) {
        self.text = text
        self.link = link
    }

    var body: some View {
        Group {
            if let link {
                Text(text + " ") + Text(Self.linked(link.title, to: link.url))
            } else {
                Text(text)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private static func linked(_ title: String, to url: URL) -> AttributedString {
        var attributed = AttributedString(title)
        attributed.link = url
        return attributed
    }
}

struct CopyCommandRow: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer()
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
        }
    }
}

extension View {
    func settingsPage(_ tab: SettingsTab) -> some View {
        formStyle(.grouped)
            .tint(.effectiveAccent)
            .navigationTitle(tab.title)
    }
}

func customBadge(text: String) -> some View {
    Text(text)
        .foregroundStyle(.secondary)
        .font(.footnote.bold())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .secondarySystemFill))
        .clipShape(.capsule)
}

func lighterColor(from nsColor: NSColor, amount: CGFloat = 0.14) -> Color {
    let srgb = nsColor.usingColorSpace(.sRGB) ?? nsColor
    var (r, g, b, a): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
    srgb.getRed(&r, green: &g, blue: &b, alpha: &a)

    func lighten(_ c: CGFloat) -> CGFloat {
        let increased = c + (1.0 - c) * amount
        return min(max(increased, 0), 1)
    }

    return Color(red: Double(lighten(r)), green: Double(lighten(g)), blue: Double(lighten(b)), opacity: Double(a))
}
