import AppKit
import Defaults
import SwiftUI

struct ScreenshotBanner: Equatable {
    let item: ClipItem
}

@MainActor
final class ScreenshotBannerStore: ObservableObject {
    static let shared = ScreenshotBannerStore()
    static let duration: Double = 5

    @Published private(set) var banner: ScreenshotBanner?

    private var bannerTask: Task<Void, Never>?

    private init() {}

    func show(_ item: ClipItem) {
        guard Defaults[.vitrinEnabled] else { return }
        AgentSessionStore.shared.dismissBanner()
        DevNotificationStore.shared.dismissBanner()
        bannerTask?.cancel()
        withAnimation(.smooth) { banner = ScreenshotBanner(item: item) }
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.duration))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    func dismissBanner() {
        bannerTask?.cancel()
        guard banner != nil else { return }
        withAnimation(.smooth) { banner = nil }
    }
}

@MainActor
final class VitrinNavigation: ObservableObject {
    static let shared = VitrinNavigation()
    @Published var requestedFilter: VitrinFilter?
    private init() {}
}

struct ScreenshotBannerView: View {
    @Environment(\.nubrixPalette) private var palette
    @EnvironmentObject var vm: NubrixViewModel
    let banner: ScreenshotBanner

    var body: some View {
        let height = vm.effectiveClosedNotchHeight
        HStack(spacing: 0) {
            HStack {
                thumbnail(height: height)
                Spacer(minLength: 0)
            }
            .frame(width: 70, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 10)

            VStack(alignment: .trailing, spacing: 0) {
                Text("Screenshot")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1)
                if banner.item.imageWidth > 0 {
                    Text("\(banner.item.imageWidth)\u{00D7}\(banner.item.imageHeight)")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 90, alignment: .trailing)
        }
        .frame(height: height, alignment: .center)
    }

    private func thumbnail(height: CGFloat) -> some View {
        BannerThumbnail(item: banner.item, side: max(16, height - 8))
    }
}

private struct BannerThumbnail: View {
    @Environment(\.nubrixPalette) private var palette
    let item: ClipItem
    let side: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Color.clear
            .overlay {
                if let shown = image ?? ClipStore.shared.cachedThumbnail(for: item) {
                    Image(nsImage: shown)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "camera.viewfinder")
                        .foregroundStyle(palette.foreground)
                }
            }
            .frame(width: side * 1.4, height: side)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(palette.foreground.opacity(0.25), lineWidth: 0.5))
            .padding(.leading, 6)
            .onDrag { ClipStore.shared.itemProvider(for: item) }
            .task(id: item.id) {
                image = await ClipStore.shared.thumbnail(for: item)
            }
    }
}

struct ScreenshotAccessPrompt: View {
    @Environment(\.nubrixPalette) private var palette
    @ObservedObject var access = ScreenshotAccess.shared
    @Default(.vitrinEnabled) var enabled
    @Default(.vitrinCaptureImages) var captureImages
    @Default(.vitrinCaptureScreenshots) var captureScreenshots
    @Default(.vitrinScreenshotPromptDismissed) var dismissed

    var body: some View {
        if enabled, captureImages, captureScreenshots, !access.hasAccess, !dismissed {
            HStack(spacing: 6) {
                Button {
                    access.requestAccess()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                        Text("Allow screenshots")
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.foreground)
                }
                .buttonStyle(.plain)
                .help("Let Vitrin see new screenshots saved to your screenshot folder")
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.foreground.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Hide this")
            }
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(Color.accentColor.opacity(0.35)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 0.5))
        }
    }
}
