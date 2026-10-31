import SwiftUI

enum MirrorCameraState: Equatable {
    case starting
    case running
    case denied
    case unavailable
}

enum MirrorMetrics {
    static let mediumSize = CGSize(width: 480, height: 360)
    static let largeSize = CGSize(width: 640, height: 480)
    static let controlHeight: CGFloat = 30

    static func size(large: Bool) -> CGSize { large ? largeSize : mediumSize }
}

struct MirrorChromeView<Preview: View>: View {
    let state: MirrorCameraState
    let preview: Preview
    let large: Bool
    let controlsVisible: Bool
    let onFlip: () -> Void
    let onToggleSize: () -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(white: 0.07)
            if state == .running {
                preview
            } else {
                statusView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            controls
        }
        .animation(.easeOut(duration: 0.2), value: state)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            pill(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right", title: nil, help: "Flip", action: onFlip)
                .opacity(state == .running ? 1 : 0)
                .allowsHitTesting(state == .running)
            pill(systemName: nil, title: large ? "L" : "M", help: "Size", action: onToggleSize)
            pill(systemName: "xmark", title: nil, help: "Close", action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.top, 36)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
        .opacity(controlsVisible ? 1 : 0)
        .allowsHitTesting(controlsVisible)
        .animation(.easeOut(duration: 0.16), value: controlsVisible)
    }

    @ViewBuilder
    private var statusView: some View {
        VStack(spacing: 8) {
            switch state {
            case .denied:
                Image(systemName: "video.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Camera access is off")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Button(action: onOpenSettings) {
                    Text("Open Privacy Settings")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            case .unavailable:
                Image(systemName: "web.camera")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.7))
                Text("No camera found")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Connect a camera and try again")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            default:
                Image(systemName: "web.camera")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.45))
                Text("Camera starting")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
    }

    private func pill(systemName: String?, title: String?, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: 12, weight: .semibold))
                } else if let title {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.white)
            .frame(width: MirrorMetrics.controlHeight, height: MirrorMetrics.controlHeight)
            .background(Circle().fill(Color.white.opacity(0.18)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
