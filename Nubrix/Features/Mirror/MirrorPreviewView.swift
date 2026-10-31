import AVFoundation
import AppKit
import SwiftUI

final class MirrorPreviewNSView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func setMirrored(_ mirrored: Bool) {
        guard let connection = previewLayer.connection else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = mirrored
        }
    }
}

struct MirrorPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> MirrorPreviewNSView {
        let view = MirrorPreviewNSView(session: session)
        view.setMirrored(mirrored)
        return view
    }

    func updateNSView(_ view: MirrorPreviewNSView, context: Context) {
        view.setMirrored(mirrored)
    }
}
