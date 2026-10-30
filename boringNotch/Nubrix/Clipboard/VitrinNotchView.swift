import Defaults
import SwiftUI

enum VitrinFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case images = "Images"
    case text = "Text"
    case links = "Links"

    var id: String { rawValue }

    func matches(_ item: ClipItem) -> Bool {
        switch self {
        case .all: return true
        case .images: return item.kind == .image
        case .text: return item.kind == .text
        case .links: return item.kind == .link
        }
    }
}

struct VitrinTabView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var store = ClipStore.shared
    @Default(.vitrinEnabled) var enabled
    @State private var filter: VitrinFilter = .all

    var body: some View {
        let visible = store.items.filter { filter.matches($0) }
        VStack(alignment: .leading, spacing: 8) {
            if !enabled {
                VitrinEmptyState(message: "Vitrin is off", detail: "Turn it on in Settings.")
            } else {
                chips
                if visible.isEmpty {
                    VitrinEmptyState(
                        message: store.items.isEmpty ? "Nothing copied yet" : "No matches",
                        detail: store.items.isEmpty ? "Things you copy show up here." : "Try another filter."
                    )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 8) {
                            ForEach(visible) { item in
                                VitrinCard(
                                    item: item,
                                    size: CGSize(width: 120, height: 96),
                                    onCopy: {
                                        store.copy(item)
                                        vm.close()
                                    },
                                    onPin: { store.togglePin(item) },
                                    onDelete: { store.delete(item) }
                                )
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(height: 96)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(VitrinFilter.allCases) { option in
                Button {
                    withAnimation(.smooth(duration: 0.2)) { filter = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(filter == option ? .black : .white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(filter == option ? Color.white : Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}
