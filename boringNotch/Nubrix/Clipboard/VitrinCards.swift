import SwiftUI

struct VitrinCard: View {
    let item: ClipItem
    var size: CGSize
    var scale: CGFloat = 1
    var selected: Bool = false
    var onCopy: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void
    var onAction: (ClipInsightAction) -> Void = { _ in }

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
            if let insight = ClipInsightCache.shared.insight(for: item), !insight.actions.isEmpty {
                Divider()
                ForEach(insight.actions) { action in
                    Button(action.title) { onAction(action) }
                }
            }
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
            TextCardContent(item: item, scale: scale)
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
    let item: ClipItem
    let scale: CGFloat

    var body: some View {
        let text = item.text ?? ""
        let insight = ClipInsightCache.shared.insight(for: item)
        let code = insight?.isCode ?? ClipClassifier.looksLikeCode(text)
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4 * scale) {
                if let color = insight?.color {
                    RoundedRectangle(cornerRadius: 6 * scale)
                        .fill(Color(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255, opacity: color.alpha))
                        .overlay(RoundedRectangle(cornerRadius: 6 * scale).strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                        .frame(height: 34 * scale)
                } else if code {
                    Text(ClipInsightCache.shared.cardText(for: item, language: insight?.language))
                        .font(.system(size: 10 * scale, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    Text(String(text.prefix(400)))
                        .font(.system(size: 11.5 * scale))
                        .foregroundStyle(.white.opacity(0.92))
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if insight?.color != nil {
                    Text(String(text.prefix(60)))
                        .font(.system(size: 10 * scale, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 9 * scale)
            .padding(.top, 9 * scale)
            .padding(.bottom, insight == nil ? 6 * scale : 22 * scale)
            if let insight {
                InsightBadge(insight: insight, scale: scale)
                    .padding(5 * scale)
            }
        }
    }
}

struct InsightBadge: View {
    let insight: ClipInsight
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 4 * scale) {
            if let color = insight.color {
                Circle()
                    .fill(Color(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255, opacity: color.alpha))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
                    .frame(width: 8 * scale, height: 8 * scale)
            }
            Text(insight.date ?? insight.label)
                .lineLimit(1)
        }
        .font(.system(size: 9 * scale, weight: .medium).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 2 * scale)
        .background(Capsule().fill(Color.black.opacity(0.65)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
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
