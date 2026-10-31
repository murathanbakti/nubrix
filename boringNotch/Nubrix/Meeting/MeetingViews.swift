import SwiftUI

struct MeetingLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var watcher = MeetingWatcher.shared

    var body: some View {
        if let meeting = watcher.next {
            MeetingWingContent(
                meeting: meeting,
                now: watcher.now,
                closedHeight: vm.effectiveClosedNotchHeight,
                notchGap: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)
        }
    }

    static func extraWidth(closedHeight: CGFloat) -> CGFloat {
        MeetingWing.extraWidth(closedHeight: closedHeight)
    }
}

struct MeetingBannerView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var watcher = MeetingWatcher.shared
    let banner: MeetingBanner

    var body: some View {
        MeetingBannerContent(
            banner: banner,
            meeting: watcher.next,
            closedHeight: vm.effectiveClosedNotchHeight,
            notchGap: vm.closedNotchSize.width + 10)
    }
}

struct MeetingCardView: View {
    @ObservedObject var watcher = MeetingWatcher.shared

    var body: some View {
        if let meeting = watcher.next {
            MeetingCardContent(
                meeting: meeting,
                now: watcher.now,
                onJoin: { watcher.join() },
                onDismiss: { withAnimation(.smooth) { watcher.dismissCurrent() } })
        }
    }
}
