import SwiftUI

/// Closed notch header: symbol and title on the left, small text on the right.
struct EverydayAlertHeader: View {
    @Environment(\.nubrixPalette) private var palette
    @EnvironmentObject var vm: NubrixViewModel
    let alert: EverydayAlert

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: alert.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(alert.tint == .white ? palette.foreground : alert.tint.color)
                Text(alert.headerTitle ?? alert.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 150, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            HStack(spacing: 4) {
                if let meta = alert.meta {
                    Text(meta)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.foreground.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
