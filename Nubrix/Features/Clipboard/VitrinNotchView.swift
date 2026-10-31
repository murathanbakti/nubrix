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

    var body: some View {
        let visible = store.items.filter { filter.matches($0) }
        VStack(alignment: .leading, spacing: 10) {
            if !enabled {
                VitrinEmptyState(message: "Vitrin is off", detail: "Turn it on in Settings.")
            } else {
                VitrinChipBar(selection: $filter, counts: counts) {
                    ScreenshotAccessPrompt()
                }
                if visible.isEmpty {
                    VitrinEmptyState(
                        message: store.items.isEmpty ? "Nothing copied yet" : "No matches",
                        detail: store.items.isEmpty ? "Things you copy show up here." : "Try another filter."
                    )
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
                        }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: applyRequestedFilter)
        .onChange(of: navigation.requestedFilter) { _, _ in applyRequestedFilter() }
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
