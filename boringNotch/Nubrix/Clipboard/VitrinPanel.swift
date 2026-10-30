import AppKit
import Combine
import Defaults
import SwiftUI

final class VitrinPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class VitrinPanelModel: ObservableObject {
    @Published var query = ""
    @Published var searchActive = false
    @Published var selectedID: Int64?
    @Published var previewing = false
    @Published private(set) var results: [ClipItem] = []

    var requestClose: () -> Void = {}
    var blurSearch: () -> Void = {}
    var isSearchFocused: () -> Bool = { false }

    private let store = ClipStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        Publishers.CombineLatest(store.$items, $query)
            .map { [store] items, query in
                query.trimmingCharacters(in: .whitespaces).isEmpty ? items : store.search(query)
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] results in
                self?.results = results
                self?.validateSelection()
            }
            .store(in: &cancellables)
    }

    func reset() {
        query = ""
        searchActive = false
        selectedID = nil
        previewing = false
        results = store.items
        validateSelection()
    }

    var rows: [[ClipItem]] {
        [ClipKind.image, .text, .link].map { kind in results.filter { $0.kind == kind } }
    }

    var selectedItem: ClipItem? {
        results.first { $0.id == selectedID }
    }

    private func validateSelection() {
        defer { if selectedItem == nil { previewing = false } }
        if let selectedID, results.contains(where: { $0.id == selectedID }) { return }
        selectedID = rows.first(where: { !$0.isEmpty })?.first?.id
    }

    var selectedInsight: ClipInsight? {
        selectedItem.flatMap { ClipInsightCache.shared.insight(for: $0) }
    }

    func perform(_ action: ClipInsightAction) {
        store.copyTransformed(action.output)
        requestClose()
    }

    func stepPreview(_ delta: Int) {
        let all = rows.flatMap { $0 }
        guard let selectedID, let i = all.firstIndex(where: { $0.id == selectedID }) else { return }
        let next = min(max(i + delta, 0), all.count - 1)
        self.selectedID = all[next].id
    }

    private func position() -> (row: Int, col: Int)? {
        guard let selectedID else { return nil }
        for (r, row) in rows.enumerated() {
            if let c = row.firstIndex(where: { $0.id == selectedID }) { return (r, c) }
        }
        return nil
    }

    func move(dx: Int, dy: Int) {
        let rows = self.rows
        guard let pos = position() else {
            validateSelection()
            return
        }
        if dx != 0 {
            let c = min(max(pos.col + dx, 0), rows[pos.row].count - 1)
            selectedID = rows[pos.row][c].id
        }
        if dy != 0 {
            var r = pos.row + dy
            while rows.indices.contains(r), rows[r].isEmpty { r += dy }
            if rows.indices.contains(r) {
                selectedID = rows[r][min(pos.col, rows[r].count - 1)].id
            }
        }
    }

    func copySelected() {
        guard let item = selectedItem else { return }
        store.copy(item)
        requestClose()
    }

    func copy(_ item: ClipItem) {
        store.copy(item)
        requestClose()
    }

    func togglePin(_ item: ClipItem) {
        store.togglePin(item)
    }

    func delete(_ item: ClipItem) {
        if item.id == selectedID {
            let all = rows.flatMap { $0 }
            if let i = all.firstIndex(where: { $0.id == item.id }) {
                let rest = all.filter { $0.id != item.id }
                selectedID = rest.isEmpty ? nil : rest[min(i, rest.count - 1)].id
            }
        }
        store.delete(item)
    }

    private func handlePreview(_ event: NSEvent, mods: NSEvent.ModifierFlags, command: Bool) -> Bool {
        switch event.keyCode {
        case 53, 49:
            previewing = false
        case 36, 76:
            copySelected()
        case 123, 126:
            stepPreview(-1)
        case 124, 125:
            stepPreview(1)
        case 51, 117:
            if let item = selectedItem { delete(item) }
        default:
            let chars = event.charactersIgnoringModifiers ?? ""
            guard command else { return true }
            if chars.lowercased() == "p", let item = selectedItem {
                togglePin(item)
            } else if let n = Int(chars), n >= 1, let actions = selectedInsight?.actions, n <= actions.count {
                perform(actions[n - 1])
            } else {
                return false
            }
        }
        return true
    }

    func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = mods.contains(.command)
        let searching = isSearchFocused()
        if previewing { return handlePreview(event, mods: mods, command: command) }
        switch event.keyCode {
        case 53:
            requestClose()
            return true
        case 49:
            if searching || command { return false }
            if selectedItem != nil { previewing = true }
            return true
        case 36, 76:
            copySelected()
            return true
        case 125, 126:
            if searching { blurSearch() }
            move(dx: 0, dy: event.keyCode == 125 ? 1 : -1)
            return true
        case 123, 124:
            if searching { return false }
            move(dx: event.keyCode == 124 ? 1 : -1, dy: 0)
            return true
        case 51, 117:
            if searching && !command { return false }
            if let item = selectedItem { delete(item) }
            return true
        default:
            break
        }
        let chars = event.charactersIgnoringModifiers ?? ""
        if command {
            if chars.lowercased() == "p", let item = selectedItem {
                togglePin(item)
                return true
            }
            return false
        }
        if searching { return false }
        guard !mods.contains(.control), !mods.contains(.option), let first = chars.unicodeScalars.first,
              first.value >= 0x20, first.value != 0x7F, !(0xF700...0xF8FF).contains(first.value) else { return false }
        if chars.lowercased() == "p" {
            if let item = selectedItem { togglePin(item) }
            return true
        }
        if chars == "/" {
            searchActive = true
            return true
        }
        query += event.characters ?? chars
        searchActive = true
        return true
    }
}

struct VitrinPanelView: View {
    @ObservedObject var model: VitrinPanelModel
    @FocusState private var searchFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchBar
            VitrinPanelRow(title: "Images", icon: "photo", items: model.rows[0], model: model)
            VitrinPanelRow(title: "Text", icon: "text.alignleft", items: model.rows[1], model: model)
            VitrinPanelRow(title: "Links", icon: "link", items: model.rows[2], model: model)
        }
        .padding(18)
        .frame(width: VitrinPanelController.size.width, height: VitrinPanelController.size.height)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black))
        .overlay {
            if model.previewing, let item = model.selectedItem {
                VitrinPreview(item: item, model: model)
                    .transition(.opacity)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onChange(of: model.searchActive) { _, active in
            searchFocus = active
        }
        .onChange(of: searchFocus) { _, focused in
            model.searchActive = focused
            if focused {
                DispatchQueue.main.async {
                    if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            searchField
            ScreenshotAccessPrompt(scale: 1.1)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)
            TextField("Search  (/ to focus)", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .focused($searchFocus)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.gray)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
    }
}

private struct VitrinPreview: View {
    let item: ClipItem
    @ObservedObject var model: VitrinPanelModel
    @State private var image: NSImage?

    var body: some View {
        let insight = ClipInsightCache.shared.insight(for: item)
        VStack(alignment: .leading, spacing: 12) {
            header(insight)
            content(insight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            actionBar(insight)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.97)))
    }

    private func header(_ insight: ClipInsight?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.isScreenshot ? "camera.viewfinder" : item.kind == .image ? "photo" : item.kind == .link ? "link" : "text.alignleft")
                .foregroundStyle(.gray)
            if let insight, item.kind == .text {
                InsightBadge(insight: insight, scale: 1.2)
            }
            if item.isScreenshot {
                Text("Screenshot").font(.system(size: 11)).foregroundStyle(.gray)
            } else if let app = item.sourceApp {
                Text(app).font(.system(size: 11)).foregroundStyle(.gray)
            }
            Spacer()
            Text("\u{2190} \u{2192} browse   \u{23CE} copy   Space / Esc close")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
        }
    }

    @ViewBuilder
    private func content(_ insight: ClipInsight?) -> some View {
        switch item.kind {
        case .image:
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if item.imageWidth > 0 {
                    Text("\(item.imageWidth)\u{00D7}\(item.imageHeight)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                }
            }
            .task(id: item.id) {
                image = ClipStore.shared.fullImage(for: item)
            }
        case .link:
            let text = item.text ?? ""
            let url = URL(string: text)
            VStack(alignment: .leading, spacing: 10) {
                Text(url?.host ?? text)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let scheme = url?.scheme {
                    Text(scheme.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                ScrollView {
                    Text(text)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        case .text:
            let text = item.text ?? ""
            ScrollView([.vertical, .horizontal]) {
                if insight?.isCode == true {
                    Text(ClipInsightCache.shared.previewText(for: item, language: insight?.language))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Text(String(text.prefix(20_000)))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        }
    }

    @ViewBuilder
    private func actionBar(_ insight: ClipInsight?) -> some View {
        let actions = Array((insight?.actions ?? []).prefix(9))
        if !actions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        Button {
                            model.perform(action)
                        } label: {
                            HStack(spacing: 6) {
                                Text("\u{2318}\(index + 1)")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.gray)
                                Text(action.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct VitrinPanelRow: View {
    let title: String
    let icon: String
    let items: [ClipItem]
    @ObservedObject var model: VitrinPanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 11, weight: .semibold))
                Text("\(items.count)").font(.system(size: 10).monospacedDigit()).opacity(0.6)
            }
            .foregroundStyle(.gray)
            .padding(.horizontal, 2)
            if items.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(height: 104)
                    .overlay(Text("Nothing here").font(.caption).foregroundStyle(.gray.opacity(0.7)))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(items) { item in
                                VitrinCard(
                                    item: item,
                                    size: CGSize(width: 180, height: 104),
                                    scale: 1.2,
                                    selected: model.selectedID == item.id,
                                    onCopy: { model.copy(item) },
                                    onPin: { model.togglePin(item) },
                                    onDelete: { model.delete(item) },
                                    onAction: { model.perform($0) }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(2)
                    }
                    .frame(height: 108)
                    .onChange(of: model.selectedID) { _, id in
                        if let id, items.contains(where: { $0.id == id }) {
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                        }
                    }
                }
            }
        }
    }
}

@MainActor
final class VitrinPanelController {
    static let shared = VitrinPanelController()
    static let size = CGSize(width: 880, height: 480)

    private var panel: VitrinPanel?
    private let model = VitrinPanelModel()

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        guard Defaults[.vitrinEnabled], ClipStore.shared.isReady else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reset()
        let screen = NSScreen.screen(withUUID: BoringViewCoordinator.shared.selectedScreenUUID) ?? NSScreen.main ?? NSScreen.screens.first
        if let screen {
            let size = Self.size
            let top = screen.visibleFrame.maxY - 6
            panel.setFrame(
                NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height),
                display: false
            )
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func makePanel() -> VitrinPanel {
        let panel = VitrinPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: VitrinPanelView(model: model))
        panel.keyHandler = { [weak self] event in self?.model.handle(event) ?? false }
        panel.onResignKey = { [weak self] in self?.close() }
        model.requestClose = { [weak self] in self?.close() }
        model.isSearchFocused = { [weak panel] in
            (panel?.firstResponder as? NSTextView)?.isFieldEditor == true
        }
        model.blurSearch = { [weak self, weak panel] in
            panel?.makeFirstResponder(nil)
            self?.model.searchActive = false
        }
        return panel
    }
}
