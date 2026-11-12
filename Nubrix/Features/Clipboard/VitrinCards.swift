import SwiftUI

enum VitrinMetrics {
    static let cornerRadius: CGFloat = 10
    static func fill(_ p: ThemePalette) -> Color { p.foreground.opacity(0.06) }
    static func fillHover(_ p: ThemePalette) -> Color { p.foreground.opacity(0.10) }
    static func stroke(_ p: ThemePalette) -> Color { p.foreground.opacity(0.08) }
    static func strokeHover(_ p: ThemePalette) -> Color { p.foreground.opacity(0.18) }
    static func meta(_ p: ThemePalette) -> Color { p.foreground.opacity(0.5) }
}

enum VitrinAge {
    static func label(from date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}

struct VitrinCard: View {
    @Environment(\.nubrixPalette) private var palette
    let item: ClipItem
    var size: CGSize
    var scale: CGFloat = 1
    var selected: Bool = false
    var now: Date = Date()
    var forceHover: Bool = false
    var onCopy: () -> Void
    var onPin: () -> Void
    var onDelete: () -> Void
    var onAction: (ClipInsightAction) -> Void = { _ in }

    @State private var hoverState = false
    @State private var entry: ClipInsightEntry?

    private var hovering: Bool { hoverState || forceHover }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: VitrinMetrics.cornerRadius * scale, style: .continuous)
    }

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .background(hovering ? VitrinMetrics.fillHover(palette) : VitrinMetrics.fill(palette))
            .clipShape(shape)
            .overlay(shape.strokeBorder(hovering ? VitrinMetrics.strokeHover(palette) : VitrinMetrics.stroke(palette), lineWidth: 1))
            .overlay {
                if selected {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) { pinButton }
            .contentShape(shape)
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.snappy(duration: 0.18), value: hovering)
            .onHover { hoverState = $0 }
            .onTapGesture(perform: onCopy)
            .onDrag { ClipStore.shared.itemProvider(for: item) }
            .task(id: item.id) {
                guard item.kind != .image else { return }
                entry = await ClipInsightCache.shared.entry(for: item)
            }
            .contextMenu {
                Button("Copy", action: onCopy)
                Button(item.pinned ? "Unpin" : "Pin", action: onPin)
                if let insight = (entry ?? ClipInsightCache.shared.cachedEntry(id: item.id))?.insight, !insight.actions.isEmpty {
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
    private var pinButton: some View {
        if hovering {
            Button(action: onPin) {
                Image(systemName: item.pinned ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20 * scale, height: 20 * scale)
                    .background(Circle().fill(Color.black.opacity(0.6)))
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6 * scale)
            .help(item.pinned ? "Unpin" : "Pin")
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image:
            ImageCardContent(item: item, scale: scale, now: now, hovering: hovering)
        case .text:
            TextCardContent(item: item, entry: entry, scale: scale, now: now)
        case .link:
            LinkCardContent(item: item, scale: scale, now: now)
        }
    }
}

private struct PinDot: View {
    let scale: CGFloat

    var body: some View {
        Image(systemName: "pin.fill")
            .font(.system(size: 7 * scale, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 14 * scale, height: 14 * scale)
            .background(Circle().fill(Color.orange))
    }
}

private struct CardFooter: View {
    @Environment(\.nubrixPalette) private var palette
    let item: ClipItem
    let glyph: String
    let scale: CGFloat
    let now: Date
    var detail: String?

    var body: some View {
        HStack(spacing: 4 * scale) {
            Image(systemName: glyph)
                .font(.system(size: 9 * scale, weight: .medium))
            Text(VitrinAge.label(from: item.createdAt, now: now))
                .lineLimit(1)
            if let detail {
                Spacer(minLength: 4 * scale)
                Text(detail)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.system(size: 9.5 * scale, weight: .medium))
        .foregroundStyle(VitrinMetrics.meta(palette))
    }
}

private struct ImageCardContent: View {
    @Environment(\.nubrixPalette) private var palette
    let item: ClipItem
    let scale: CGFloat
    let now: Date
    let hovering: Bool
    @State private var image: NSImage?

    var body: some View {
        palette.foreground.opacity(0.05)
            .overlay {
                if let shown = image ?? ClipStore.shared.cachedThumbnail(for: item) {
                    Image(nsImage: shown)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 20 * scale))
                        .foregroundStyle(palette.secondary)
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 32 * scale)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                CardFooter(
                    item: item,
                    glyph: item.isScreenshot ? "camera.viewfinder" : "photo",
                    scale: scale,
                    now: now,
                    detail: hovering && item.imageWidth > 0 ? "\(item.imageWidth)\u{00D7}\(item.imageHeight)" : nil
                )
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 8 * scale)
                .padding(.bottom, 6 * scale)
            }
            .overlay(alignment: .topLeading) {
                if item.pinned {
                    PinDot(scale: scale).padding(6 * scale)
                }
            }
            .clipped()
            .task(id: item.id) {
                image = await ClipStore.shared.thumbnail(for: item)
            }
    }
}

private struct TextCardContent: View {
    @Environment(\.nubrixPalette) private var palette
    let item: ClipItem
    let entry: ClipInsightEntry?
    let scale: CGFloat
    let now: Date

    var body: some View {
        let text = item.previewOrEmpty
        let current = entry ?? ClipInsightCache.shared.cachedEntry(id: item.id)
        let insight = current?.insight
        VStack(alignment: .leading, spacing: 4 * scale) {
            if insight != nil || item.pinned {
                HStack(spacing: 4 * scale) {
                    if item.pinned { PinDot(scale: scale) }
                    if let insight { InsightBadge(insight: insight, scale: scale) }
                }
            }
            if let color = insight?.color {
                RoundedRectangle(cornerRadius: 6 * scale, style: .continuous)
                    .fill(Color(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255, opacity: color.alpha))
                    .overlay(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous).strokeBorder(palette.foreground.opacity(0.25), lineWidth: 1))
                    .frame(height: 24 * scale)
                Text(String(text.prefix(60)))
                    .font(.system(size: 10.5 * scale, design: .monospaced))
                    .foregroundStyle(palette.foreground.opacity(0.8))
                    .lineLimit(1)
            } else if let code = current?.cardText {
                Text(code)
                    .font(.system(size: 10.5 * scale, design: .monospaced))
                    .foregroundStyle(palette.foreground.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                Text(String(text.prefix(400)))
                    .font(.system(size: 11.5 * scale))
                    .foregroundStyle(palette.foreground.opacity(0.9))
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            Spacer(minLength: 0)
            CardFooter(item: item, glyph: "text.alignleft", scale: scale, now: now)
        }
        .padding(8 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct InsightBadge: View {
    @Environment(\.nubrixPalette) private var palette
    let insight: ClipInsight
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 4 * scale) {
            if let color = insight.color {
                Circle()
                    .fill(Color(.sRGB, red: Double(color.red) / 255, green: Double(color.green) / 255, blue: Double(color.blue) / 255, opacity: color.alpha))
                    .overlay(Circle().strokeBorder(palette.foreground.opacity(0.4), lineWidth: 0.5))
                    .frame(width: 7 * scale, height: 7 * scale)
            }
            Text(insight.date ?? insight.label)
                .lineLimit(1)
        }
        .font(.system(size: 9 * scale, weight: .semibold).monospacedDigit())
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 6 * scale)
        .frame(height: 14 * scale)
        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
    }
}

private struct LinkCardContent: View {
    @Environment(\.nubrixPalette) private var palette
    let item: ClipItem
    let scale: CGFloat
    let now: Date

    var body: some View {
        let parts = LinkParts(item.previewOrEmpty)
        VStack(alignment: .leading, spacing: 3 * scale) {
            HStack(spacing: 5 * scale) {
                if item.pinned { PinDot(scale: scale) }
                Image(systemName: "link")
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22 * scale, height: 22 * scale)
                    .background(Circle().fill(Color.accentColor.opacity(0.18)))
            }
            .padding(.bottom, 3 * scale)
            Text(parts.host)
                .font(.system(size: 12 * scale, weight: .semibold))
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
                .truncationMode(.middle)
            if !parts.rest.isEmpty {
                Text(parts.rest)
                    .font(.system(size: 10.5 * scale))
                    .foregroundStyle(palette.foreground.opacity(0.55))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            CardFooter(item: item, glyph: "link", scale: scale, now: now)
        }
        .padding(8 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var viewport: CGFloat = 0
}

private struct ScrollMetricsKey: PreferenceKey {
    static var defaultValue = ScrollMetrics()
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        let next = nextValue()
        if next.content > 0 { value.offset = next.offset; value.content = next.content }
        if next.viewport > 0 { value.viewport = next.viewport }
    }
}

struct VitrinCardScroller<Content: View>: View {
    var height: CGFloat
    var spacing: CGFloat
    var inset: CGFloat
    var vertical: CGFloat
    @ViewBuilder var content: Content

    @State private var metrics = ScrollMetrics()
    private let fade: CGFloat = 16
    private let space = "vitrin.scroller"

    var body: some View {
        let leading = metrics.offset < -2
        let trailing = metrics.content > metrics.viewport + 2 && metrics.content + metrics.offset > metrics.viewport + 2
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: spacing) { content }
                .padding(.horizontal, inset)
                .padding(.vertical, vertical)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ScrollMetricsKey.self,
                            value: ScrollMetrics(offset: proxy.frame(in: .named(space)).minX, content: proxy.size.width)
                        )
                    }
                )
        }
        .coordinateSpace(name: space)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ScrollMetricsKey.self, value: ScrollMetrics(viewport: proxy.size.width))
            }
        )
        .onPreferenceChange(ScrollMetricsKey.self) { metrics = $0 }
        .mask {
            HStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(leading ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
                Rectangle().fill(Color.black)
                LinearGradient(colors: [.black, .black.opacity(trailing ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
            }
            .animation(.smooth(duration: 0.2), value: leading)
            .animation(.smooth(duration: 0.2), value: trailing)
        }
        .frame(height: height)
    }
}

struct VitrinCardRow: View {
    let items: [ClipItem]
    var onCopy: (ClipItem) -> Void
    var onPin: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void
    var onAction: (ClipInsightAction) -> Void

    static let defaultCardSize = CGSize(width: 145, height: 100)

    var cardSize: CGSize = Self.defaultCardSize
    var scale: CGFloat = 1

    var body: some View {
        ScrollViewReader { proxy in
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VitrinCardScroller(height: cardSize.height + 6, spacing: 10, inset: 6, vertical: 3) {
                    ForEach(items) { item in
                        VitrinCard(
                            item: item,
                            size: cardSize,
                            scale: scale,
                            now: context.date,
                            onCopy: { onCopy(item) },
                            onPin: { onPin(item) },
                            onDelete: { onDelete(item) },
                            onAction: onAction
                        )
                        .id(item.id)
                    }
                }
            }
            .onChange(of: items.first?.id) { _, id in
                if let id {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .leading) }
                }
            }
        }
    }
}

struct VitrinChipBar<Trailing: View>: View {
    @Environment(\.nubrixPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: VitrinFilter
    let counts: [VitrinFilter: Int]
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            ForEach(VitrinFilter.allCases.filter { $0 == .all || (counts[$0] ?? 0) > 0 || $0 == selection }) { option in
                chip(option)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 6)
        .frame(height: 20)
    }

    private func chip(_ option: VitrinFilter) -> some View {
        let selected = selection == option
        return Button {
            withAnimation(.smooth(duration: 0.2)) { selection = option }
        } label: {
            HStack(spacing: 4) {
                Text(option.rawValue)
                if option != .all, let count = counts[option] {
                    Text("\(count)")
                        .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                        .opacity(0.55)
                }
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(selected ? (colorScheme == .dark ? Color.black : Color.white) : palette.foreground.opacity(0.75))
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(selected ? palette.foreground : palette.foreground.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

struct VitrinSection: View {
    @Environment(\.nubrixPalette) private var palette
    let title: String
    let icon: String
    let items: [ClipItem]
    var selectedID: Int64?
    var onCopy: (ClipItem) -> Void
    var onPin: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void
    var onAction: (ClipInsightAction) -> Void

    static let cardSize = CGSize(width: 180, height: 112)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                Text("\(items.count)")
                    .font(.system(size: 10.5, weight: .regular).monospacedDigit())
                    .opacity(0.7)
            }
            .foregroundStyle(palette.foreground.opacity(0.55))
            .padding(.horizontal, 2)
            if items.isEmpty {
                RoundedRectangle(cornerRadius: VitrinMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(palette.foreground.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: Self.cardSize.height)
                    .overlay(Text("Nothing here").font(.system(size: 11)).foregroundStyle(palette.foreground.opacity(0.4)))
                    .padding(.vertical, 4)
            } else {
                ScrollViewReader { proxy in
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        VitrinCardScroller(height: Self.cardSize.height + 8, spacing: 12, inset: 4, vertical: 4) {
                            ForEach(items) { item in
                                VitrinCard(
                                    item: item,
                                    size: Self.cardSize,
                                    selected: selectedID == item.id,
                                    now: context.date,
                                    onCopy: { onCopy(item) },
                                    onPin: { onPin(item) },
                                    onDelete: { onDelete(item) },
                                    onAction: onAction
                                )
                                .id(item.id)
                            }
                        }
                    }
                    .onChange(of: selectedID) { _, id in
                        if let id, items.contains(where: { $0.id == id }) {
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                        }
                    }
                }
            }
        }
    }
}

struct VitrinEmptyState: View {
    @Environment(\.nubrixPalette) private var palette
    var message = "Nothing copied yet"
    var detail = "Things you copy show up here."

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 18))
                .foregroundStyle(palette.secondary)
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.foreground)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(palette.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
