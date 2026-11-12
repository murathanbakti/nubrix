import SwiftUI

struct ThemeBackground<S: Shape>: View {
    let theme: NubrixTheme
    let shape: S
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    private var gradient: LinearGradient {
        let a = theme.gradientAngle * .pi / 180
        let dx = cos(a) / 2
        let dy = sin(a) / 2
        return LinearGradient(
            colors: [theme.primaryColor.color, theme.secondaryColor.color],
            startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
            endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
        )
    }

    var body: some View {
        ZStack {
            switch theme.background {
            case .solid:
                shape.fill(theme.primaryColor.color.opacity(theme.opacity))
            case .gradient:
                shape.fill(gradient).opacity(theme.opacity)
            case .blur:
                VisualEffectView(
                    material: theme.blurMaterial.material,
                    blendingMode: blending,
                    appearance: NSAppearance(named: theme.resolvedForeground == .light ? .darkAqua : .aqua),
                    state: .active
                )
                .clipShape(shape)
                shape.fill(theme.primaryColor.color.opacity(theme.opacity))
            }
            if theme.showsBorder {
                shape.stroke(ThemePalette(theme: theme).foreground.opacity(theme.borderOpacity), lineWidth: 1)
            }
        }
    }
}
