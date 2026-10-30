import SwiftUI

enum MirrorCameraState: Equatable {
    case starting
    case running
    case denied
    case unavailable
}

enum MirrorMetrics {
    static let sizes: [CGSize] = [
        CGSize(width: 240, height: 180),
        CGSize(width: 320, height: 240),
        CGSize(width: 440, height: 330)
    ]
    static let labels = ["S", "M", "L"]
    static let cornerRadius: CGFloat = 22

    static func clamp(_ index: Int) -> Int {
        min(max(index, 0), sizes.count - 1)
    }
}

struct MirrorChromeView<Preview: View>: View {
    let state: MirrorCameraState
    let sizeIndex: Int
    var forceControls = false
    let preview: Preview
    let onFlip: () -> Void
    let onSize: (Int) -> Void
    let onClose: () -> Void
    let onOpenSettings: () -> Void

    @State private var hovering = false

    private var controlsVisible: Bool {
        hovering || forceControls || state != .running
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MirrorMetrics.cornerRadius, style: .continuous)
        ZStack {
            Color.black
            if state == .running {
                preview
                    .transition(.opacity)
            } else {
                statusView
            }
        }
        .animation(.easeOut(duration: 0.2), value: state)
        .overlay(alignment: .bottom) {
            controlBar
                .opacity(controlsVisible ? 1 : 0)
                .allowsHitTesting(controlsVisible)
                .animation(.easeOut(duration: 0.15), value: controlsVisible)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .contentShape(shape)
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var statusView: some View {
        VStack(spacing: 8) {
            switch state {
            case .denied:
                Image(systemName: "video.slash")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Camera access is off")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Button(action: onOpenSettings) {
                    Text("Open Privacy Settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            case .unavailable:
                Image(systemName: "web.camera")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                Text("No camera found")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Connect a camera and try again")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            default:
                Image(systemName: "video.slash")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                Text("Camera starting")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.bottom, 26)
    }

    private var controlBar: some View {
        HStack(spacing: 8) {
            roundButton("arrow.left.and.right.righttriangle.left.righttriangle.right", help: "Flip", action: onFlip)
            sizePicker
            Spacer(minLength: 0)
            roundButton("xmark", help: "Close", action: onClose)
        }
        .padding(.horizontal, 10)
        .padding(.top, 22)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func roundButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.18)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var sizePicker: some View {
        HStack(spacing: 2) {
            ForEach(MirrorMetrics.labels.indices, id: \.self) { index in
                let selected = index == sizeIndex
                Button {
                    onSize(index)
                } label: {
                    Text(MirrorMetrics.labels[index])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? Color.black : Color.white)
                        .frame(width: 24, height: 22)
                        .background(Capsule().fill(selected ? Color.white : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.18)))
    }
}
