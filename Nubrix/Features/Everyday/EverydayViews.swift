import SwiftUI

/// Closed notch header: symbol and title on the left, small text on the right.
struct EverydayAlertHeader: View {
    @EnvironmentObject var vm: NubrixViewModel
    let alert: EverydayAlert

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: alert.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(alert.tint.color)
                Text(alert.headerTitle ?? alert.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
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
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

/// Card under the notch: round icon, title, detail and an optional button.
struct EverydayAlertCard: View {
    @EnvironmentObject var vm: NubrixViewModel
    @ObservedObject var store = EverydayAlertStore.shared
    let alert: EverydayAlert

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let detail = alert.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action = alert.action {
                EverydayCapsuleButton(title: action.label) { store.perform(action) }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(width: 300 + vm.closedNotchSize.width + 10)
        .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity), removal: .opacity))
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(alert.tint.color.opacity(0.35))
                .frame(width: 44, height: 44)
                .blur(radius: 14)
            Circle()
                .fill(alert.tint.color.opacity(0.18))
                .frame(width: 40, height: 40)
            Image(systemName: alert.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(alert.tint.color)
                .frame(width: 32, height: 32)
        }
        .frame(width: 40, height: 40)
    }
}

struct EverydayCapsuleButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(Capsule().fill(Color.white.opacity(hovering ? 0.18 : 0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
