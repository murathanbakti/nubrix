import SwiftUI

enum MirrorCameraState: Equatable {
    case starting
    case running
    case denied
    case unavailable
}

enum MirrorMetrics {
    static let aspect: CGFloat = 4.0 / 3.0
    static let cornerRadius: CGFloat = 12
    static let controlSize: CGFloat = 28
    static let controlSpacing: CGFloat = 14
}

struct MirrorChromeView<Preview: View>: View {
    let state: MirrorCameraState
    let preview: Preview
    let onFlip: () -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: MirrorMetrics.controlSpacing) {
            roundButton("arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Flip", action: onFlip)
                .opacity(state == .running ? 1 : 0)
                .allowsHitTesting(state == .running)
            screen
            roundButton("xmark", help: "Close", action: onClose)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var screen: some View {
        let shape = RoundedRectangle(cornerRadius: MirrorMetrics.cornerRadius, style: .continuous)
        return ZStack {
            Color(white: 0.07)
            if state == .running {
                preview
            } else {
                statusView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(MirrorMetrics.aspect, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: state)
    }

    @ViewBuilder
    private var statusView: some View {
        VStack(spacing: 6) {
            switch state {
            case .denied:
                Image(systemName: "video.slash")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Camera access is off")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Button(action: onOpenSettings) {
                    Text("Open Privacy Settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            case .unavailable:
                Image(systemName: "web.camera")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.7))
                Text("No camera found")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Connect a camera and try again")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            default:
                Image(systemName: "web.camera")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.45))
                Text("Camera starting")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 8)
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: MirrorMetrics.controlSize, height: MirrorMetrics.controlSize)
                .background(Circle().fill(Color.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
