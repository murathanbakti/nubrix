import Defaults
import SwiftUI

enum VitrinFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case images = "Images"
    case screenshots = "Screenshots"
    case text = "Text"
    case links = "Links"

    var id: String { rawValue }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .images: return item.kind == .image
        case .screenshots: return item.isScreenshot
        case .text: return item.kind == .text
        case .links: return item.kind == .link
        }
    }
}

struct VitrinTabView: View {
    @EnvironmentObject var vm: NubrixViewModel
    @ObservedObject var store = ClipStore.shared
    @Default(.vitrinEnabled) var enabled
    @ObservedObject var navigation = VitrinNavigation.shared
    @State private var filter: VitrinFilter = .all
    @ObservedObject var access = ScreenshotAccess.shared
    @Default(.vitrinKeyResetNotice) var keyResetNotice

    var body: some View {
        let visible = store.items.filter { filter.matches($0) }
        let screenshotsEmpty = filter == .screenshots && !store.items.isEmpty
        GeometryReader { proxy in
            let chipHeight: CGFloat = 20
            let gap: CGFloat = 8
            let cardHeight = min(100, max(64, floor(proxy.size.height - chipHeight - gap - 6)))
            let cardSize = CGSize(width: (cardHeight * 1.45).rounded(), height: cardHeight)
            let scale = min(1, max(0.85, cardHeight / 100))
            VStack(alignment: .leading, spacing: gap) {
                if !enabled {
                    VitrinEmptyState(message: "Vitrin is off", detail: "Turn it on in Settings.")
                } else if let lockedDetail {
                    VitrinEmptyState(message: "Vitrin is locked", detail: lockedDetail)
                } else {
                    VitrinChipBar(selection: $filter, counts: counts) {
                        ScreenshotAccessPrompt()
                        if filter == .screenshots && access.hasAccess {
                            ScreenshotDragHint()
                        }
                    }
                    if visible.isEmpty {
                        if store.items.isEmpty && keyResetNotice {
                            VitrinEmptyState(
                                message: "History was reset",
                                detail: "Its encryption key was no longer in your keychain."
                            )
                        } else {
                            VitrinEmptyState(
                                message: store.items.isEmpty ? "Nothing copied yet" : screenshotsEmpty ? "No screenshots yet" : "No matches",
                                detail: store.items.isEmpty ? "Things you copy show up here." : screenshotsEmpty ? "Saved screenshots show up here. Dragged previews aren't saved." : "Try another filter."
                            )
                        }
                    } else {
                        VitrinCardRow(
                            items: visible,
                            onCopy: { item in
                                store.copy(item)
                                vm.close()
                            },
                            onPin: { store.togglePin($0) },
                            onDelete: { store.delete($0) },
                            onAction: { action in
                                store.copyTransformed(action.output)
                                vm.close()
                            },
                            cardSize: cardSize,
                            scale: scale
                        )
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: applyRequestedFilter)
        .onChange(of: navigation.requestedFilter) { _, _ in applyRequestedFilter() }
    }

    private var lockedDetail: String? {
        switch store.vaultState {
        case .locked: return "Allow keychain access in Settings, Vitrin."
        case .failed: return "Open Settings, Vitrin to retry."
        case .off, .opening, .ready: return nil
        }
    }

    private var counts: [VitrinFilter: Int] {
        Dictionary(uniqueKeysWithValues: VitrinFilter.allCases.map { option in
            (option, store.items.filter { option.matches($0) }.count)
        })
    }

    private func applyRequestedFilter() {
        guard let requested = navigation.requestedFilter else { return }
        filter = requested
        navigation.requestedFilter = nil
    }
}

private struct ScreenshotDragHint: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
            Text("Dragged previews aren't saved")
                .lineLimit(1)
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(VitrinMetrics.meta)
        .help("macOS saves a screenshot only after its floating preview closes on its own. If you drag the preview somewhere or swipe it away, no file is written, so Vitrin can't show it. Let the preview finish first, or turn off Show Floating Thumbnail in the Screenshot app's Options (\u{21E7}\u{2318}5).")
    }
}
