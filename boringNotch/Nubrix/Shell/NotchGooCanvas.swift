import SwiftUI

struct NotchGooCanvas: View {
    let geometry: NotchExtensionGeometry
    let progress: CGFloat

    var body: some View {
        Canvas { context, _ in
            if geometry.detached {
                drawDetached(&context)
            } else {
                drawAttached(&context)
            }
        }
        .frame(width: geometry.canvas.width, height: geometry.canvas.height)
        .allowsHitTesting(false)
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -geometry.canvas.minX, dy: -geometry.canvas.minY)
    }

    private func drawDetached(_ context: inout GraphicsContext) {
        let blob = NotchExtensionTimeline.blob(progress, geometry)
        let notch = geometry.notch
        let anchor = local(CGRect(x: notch.minX, y: -40, width: notch.width, height: notch.height + 40))
        context.fill(
            Path(roundedRect: anchor, cornerRadius: NotchExtensionMetrics.closedBottomRadius, style: .continuous),
            with: .color(.black)
        )
        let offset = CGAffineTransform(translationX: -geometry.canvas.minX, y: -geometry.canvas.minY)
        for bridge in blob.bridges {
            context.fill(bridge.applying(offset), with: .color(.black))
        }
        context.fill(
            Path(roundedRect: local(blob.rect), cornerRadius: blob.radius, style: .continuous),
            with: .color(.black)
        )
    }

    private func drawAttached(_ context: inout GraphicsContext) {
        let sheet = NotchExtensionTimeline.sheet(progress, geometry)
        let shape = NotchShape(topCornerRadius: sheet.topRadius, bottomCornerRadius: sheet.bottomRadius)
        context.fill(shape.path(in: local(sheet.rect)), with: .color(.black))
    }
}

struct NotchTransitionView: View {
    let geometry: NotchExtensionGeometry
    let transition: NotchExtensionTransition

    var body: some View {
        TimelineView(.animation) { timeline in
            NotchGooCanvas(geometry: geometry, progress: transition.progress(at: timeline.date))
        }
    }
}
