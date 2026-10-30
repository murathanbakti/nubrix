import SwiftUI

struct VitrinCard: View {
    let item: ClipItem
    var size: CGSize
    var scale: CGFloat = 1
    var selected: Bool = false
    var onCopy: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12 * scale)
                .fill(Color.white.opacity(hovering ? 0.12 : 0.07))
            content
                .clipShape(RoundedRectangle(cornerRadius: 12 * scale))
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(4 * scale)
                    .background(Circle().fill(Color.orange))
                    .padding(5 * scale)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onPin) {
                    Image(systemName: item.pinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 10 * scale, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22 * scale, height: 22 * scale)
                        .background(Circle().fill(Color.black.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .padding(5 * scale)
                .help(item.pinned ? "Unpin" : "Pin")
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12 * scale)
                .strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(RoundedRectangle(cornerRadius: 12 * scale))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onCopy)
        .contextMenu {
            Button("Copy", action: onCopy)
            Button(item.pinned ? "Unpin" : "Pin", action: onPin)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            ImageCardContent(item: item, scale: scale)
        case .text:
            TextCardContent(text: item.text ?? "", scale: scale)
        case .link:
            LinkCardContent(text: item.text ?? "", scale: scale)
        }
    }
}

private struct ImageCardContent: View {
    let item: ClipItem
    let scale: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.25)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 22 * scale))
                    .foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if item.imageWidth > 0 {
                Text("\(item.imageWidth)\u{00D7}\(item.imageHeight)")
                    .font(.system(size: 9 * scale, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .padding(5 * scale)
            }
        }
        .task(id: item.id) {
            image = ClipStore.shared.thumbnail(for: item)
        }
    }
}

private struct TextCardContent: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        let code = ClipClassifier.looksLikeCode(text)
        Text(String(text.prefix(400)))
            .font(code ? .system(size: 10 * scale, design: .monospaced) : .system(size: 11.5 * scale))
            .foregroundStyle(.white.opacity(0.92))
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 9 * scale)
            .padding(.top, 9 * scale)
            .padding(.bottom, 6 * scale)
    }
}

private struct LinkCardContent: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        let parts = Self.parts(text)
        VStack(alignment: .leading, spacing: 4 * scale) {
            Image(systemName: "link")
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Spacer(minLength: 0)
            Text(parts.host)
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .truncationMode(.middle)
            if !parts.rest.isEmpty {
                Text(parts.rest)
                    .font(.system(size: 10 * scale))
                    .foregroundStyle(.gray)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(9 * scale)
    }

    static func parts(_ text: String) -> (host: String, rest: String) {
        guard let url = URL(string: text), var host = url.host else { return (text, "") }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var rest = url.path == "/" ? "" : url.path
        if let q = url.query { rest += "?" + q }
        return (host, rest)
    }
}

struct VitrinEmptyState: View {
    var message = "Nothing copied yet"
    var detail = "Things you copy show up here."

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.title2)
                .foregroundStyle(.gray)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
