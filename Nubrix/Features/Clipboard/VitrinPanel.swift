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
    @Published private(set) var results: [ClipItem] = [] {
        didSet { rows = Self.split(results) }
    }
    private(set) var rows: [[ClipItem]] = [[], [], []]

    var requestClose: () -> Void = {}
    var blurSearch: () -> Void = {}
    var isSearchFocused: () -> Bool = { false }

    static let searchDebounce: RunLoop.SchedulerTimeType.Stride = .milliseconds(120)

    private let store = ClipStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    init() {
        store.$items
            .sink { [weak self] _ in self?.applyQuery() }
            .store(in: &cancellables)
        $query
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .removeDuplicates()
            .debounce(for: Self.searchDebounce, scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyQuery() }
            .store(in: &cancellables)
    }

    private static func split(_ items: [ClipItem]) -> [[ClipItem]] {
        [ClipKind.image, .text, .link].map { kind in items.filter { $0.kind == kind } }
    }

    private func applyQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        searchTask?.cancel()
        if trimmed.isEmpty {
            results = store.items
            validateSelection()
            return
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            let found = await store.search(trimmed)
            guard !Task.isCancelled, query.trimmingCharacters(in: .whitespaces) == trimmed else { return }
            results = found
            validateSelection()
        }
    }

    func reset() {
        searchTask?.cancel()
        query = ""
        searchActive = false
        selectedID = nil
        previewing = false
        results = store.items
        validateSelection()
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
        selectedID.flatMap { ClipInsightCache.shared.cachedEntry(id: $0)?.insight }
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
            section("Images", "photo", model.rows[0])
            section("Text", "text.alignleft", model.rows[1])
            section("Links", "link", model.rows[2])
        }
        .padding(16)
        .frame(width: VitrinPanelController.size.width, height: VitrinPanelController.size.height)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black))
        .overlay {
            if model.previewing, let item = model.selectedItem {
                VitrinPreview(item: item, model: model)
                    .id(item.id)
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

    private func section(_ title: String, _ icon: String, _ items: [ClipItem]) -> some View {
        VitrinSection(
            title: title,
            icon: icon,
            items: items,
            selectedID: model.selectedID,
            onCopy: { model.copy($0) },
            onPin: { model.togglePin($0) },
            onDelete: { model.delete($0) },
            onAction: { model.perform($0) }
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            searchField
            ScreenshotAccessPrompt()
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
    @State private var entry: ClipInsightEntry?
    @State private var plainText: String?
    @State private var codeText: AttributedString?

    var body: some View {
        let current = entry ?? ClipInsightCache.shared.cachedEntry(id: item.id)
        let insight = current?.insight
        VStack(alignment: .leading, spacing: 12) {
            header(insight)
            content(insight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            actionBar(insight)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.97)))
        .task(id: item.id) { await load() }
    }

    private func load() async {
        switch item.kind {
        case .image:
            image = await ClipStore.shared.previewImage(for: item)
        case .link:
            entry = await ClipInsightCache.shared.entry(for: item)
            plainText = await ClipStore.shared.fullText(for: item, maxChars: 8192)
        case .text:
            let loaded = await ClipInsightCache.shared.entry(for: item)
            entry = loaded
            if loaded?.insight?.isCode == true {
                codeText = await ClipInsightCache.shared.previewText(for: item, language: loaded?.insight?.language)
            } else {
                plainText = await ClipStore.shared.fullText(for: item, maxChars: 20_000)
            }
        }
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
                if let shown = image ?? ClipStore.shared.cachedPreview(for: item) {
                    Image(nsImage: shown)
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
        case .link:
            let text = plainText ?? item.previewOrEmpty
            let parts = LinkParts(text)
            VStack(alignment: .leading, spacing: 10) {
                Text(parts.host.isEmpty ? text : parts.host)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !parts.scheme.isEmpty {
                    Text(parts.scheme.uppercased())
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
            ScrollView([.vertical, .horizontal]) {
                if let codeText {
                    Text(codeText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    Text(String((plainText ?? item.previewOrEmpty).prefix(20_000)))
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

struct LinkParts {
    let scheme: String
    let host: String
    let rest: String

    init(_ text: String) {
        var remainder = Substring(text)
        if let range = remainder.range(of: "://") {
            scheme = String(remainder[remainder.startIndex..<range.lowerBound])
            remainder = remainder[range.upperBound...]
        } else {
            scheme = ""
        }
        let end = remainder.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) ?? remainder.endIndex
        var hostPart = String(remainder[remainder.startIndex..<end])
        if let at = hostPart.lastIndex(of: "@") { hostPart = String(hostPart[hostPart.index(after: at)...]) }
        if let colon = hostPart.lastIndex(of: ":"), hostPart[hostPart.index(after: colon)...].allSatisfy(\.isNumber) {
            hostPart = String(hostPart[..<colon])
        }
        if hostPart.hasPrefix("www.") { hostPart.removeFirst(4) }
        host = hostPart
        var tail = String(remainder[end...])
        if tail == "/" { tail = "" }
        rest = tail
    }
}

@MainActor
final class VitrinPanelController {
    static let shared = VitrinPanelController()
    static let size = CGSize(width: 880, height: 520)

    private var panel: VitrinPanel?
    private let model = VitrinPanelModel()
    private var sharingObserver: AnyCancellable?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        guard Defaults[.vitrinEnabled], ClipStore.shared.isReady else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        model.reset()
        let screen = NSScreen.screen(withUUID: NubrixCoordinator.shared.selectedScreenUUID) ?? NSScreen.main ?? NSScreen.screens.first
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
        sharingObserver = Publishers.CombineLatest(
            Defaults.publisher(.vitrinHideFromCapture).map(\.newValue),
            Defaults.publisher(.hideFromScreenRecording).map(\.newValue)
        )
        .map { $0 || $1 }
        .removeDuplicates()
        .receive(on: RunLoop.main)
        .sink { [weak panel] hide in
            MainActor.assumeIsolated { panel?.sharingType = hide ? .none : .readWrite }
        }
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
