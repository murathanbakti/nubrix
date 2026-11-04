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
    @EnvironmentObject var vm: NubrixViewModel
    let device: DeviceBattery

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                Text(device.name)
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

/// Card under the notch with one ring per part.
struct DeviceBatteryDropBody: View {
    @EnvironmentObject var vm: NubrixViewModel
    let device: DeviceBattery

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                ForEach(Array(device.parts.enumerated()), id: \.offset) { _, part in
                    VStack(spacing: 5) {
                        ring(part.level)
                        Text(part.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(width: 300 + vm.closedNotchSize.width + 10)
        .transition(.asymmetric(insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity), removal: .opacity))
    }

    private func ring(_ level: Int) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(level) / 100)
                .stroke(batteryRingTint(level), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(level)%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
    }
}

/// Compact rows for the battery popover.
struct DeviceBatteryList: View {
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
                        .foregroundStyle((device.lowest ?? 100) <= DeviceBatteryTracker.lowLevel ? Color.red : Color.white.opacity(0.7))
                }
                .font(.subheadline)
            }
        }
    }
}
