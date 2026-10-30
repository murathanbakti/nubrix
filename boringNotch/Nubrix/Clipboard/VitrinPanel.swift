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
        if let selectedID, results.contains(where: { $0.id == selectedID }) { return }
        selectedID = rows.first(where: { !$0.isEmpty })?.first?.id
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

    func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = mods.contains(.command)
        let searching = isSearchFocused()
        switch event.keyCode {
        case 53:
            requestClose()
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
                                    onDelete: { model.delete(item) }
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
