import SwiftUI

/// Ring color: green above 20%, orange from 11 to 20%, red at 10% or below.
func batteryRingTint(_ level: Int) -> Color {
    switch level {
    case ...10: .red
    case ...DeviceBatteryTracker.lowLevel: .orange
    default: .green
    }
}

/// Closed notch header: device on the left, level on the right.
struct DeviceBatteryBannerHeader: View {
    @Environment(\.nubrixPalette) private var palette
    @EnvironmentObject var vm: NubrixViewModel
    let device: DeviceBattery

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(palette.foreground)
                Text(device.name)
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
                if let level = device.lowest {
                    Text("\(level)%")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(batteryRingTint(level))
                }
            }
            .frame(width: 150, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

/// Compact rows for the battery popover.
struct DeviceBatteryList: View {
    @Environment(\.nubrixPalette) private var palette
    let devices: [DeviceBattery]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(devices) { device in
                HStack(spacing: 8) {
                    Image(systemName: device.kind.symbol)
                        .frame(width: 18)
                    Text(device.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(device.summary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .monospacedDigit()
                        .foregroundStyle((device.lowest ?? 100) <= DeviceBatteryTracker.lowLevel ? Color.red : palette.foreground.opacity(0.7))
                }
                .font(.subheadline)
            }
        }
    }
}
