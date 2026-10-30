import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleCalendar = Self("toggleCalendar", default: .init(.k, modifiers: [.control, .option]))
}

enum NubrixCalendarSheetMetrics {
    static let contentSize = CGSize(width: 620, height: 356)
    static let bottomInset: CGFloat = 16
    static let sideInset: CGFloat = 16

    static func sheetSize(notchHeight: CGFloat) -> CGSize {
        CGSize(
            width: contentSize.width + (NotchExtensionMetrics.attachedTopRadius + sideInset) * 2,
            height: notchHeight + contentSize.height + bottomInset
        )
    }
}

@MainActor
enum NubrixCalendarSheet {
    static let extensionID = "dev.nubrix.calendar"

    static var isActive: Bool { NotchExtensionHost.shared.isPresenting(extensionID) }

    static func toggle(screenUUID: String? = nil) {
        let notchHeight = getClosedNotchSize(screenUUID: screenUUID ?? BoringViewCoordinator.shared.selectedScreenUUID).height
        NotchExtensionHost.shared.toggle(
            id: extensionID,
            mode: .attached(size: NubrixCalendarSheetMetrics.sheetSize(notchHeight: notchHeight)),
            screenUUID: screenUUID,
            activatesOnPresent: true,
            handlesEscape: false,
            content: { NubrixCalendarSheetContent() }
        )
    }

    static func toggleUnderMouse() {
        var uuid: String?
        if Defaults[.showOnAllDisplays] {
            let mouse = NSEvent.mouseLocation
            uuid = NSScreen.screens.first { $0.frame.contains(mouse) }?.displayUUID
        }
        toggle(screenUUID: uuid)
    }

    static func dismiss(animated: Bool = true) {
        NotchExtensionHost.shared.dismiss(id: extensionID, animated: animated)
    }
}

struct NubrixCalendarSheetContent: View {
    @Environment(\.notchExtensionDismiss) private var dismiss

    var body: some View {
        NubrixCalendarView(onClose: { dismiss() })
            .padding(.horizontal, NubrixCalendarSheetMetrics.sideInset)
            .padding(.bottom, NubrixCalendarSheetMetrics.bottomInset)
    }
}

@MainActor
enum NubrixCalendarService {
    static func start() {
        KeyboardShortcuts.onKeyDown(for: .toggleCalendar) {
            Task { @MainActor in NubrixCalendarSheet.toggleUnderMouse() }
        }
    }

    static func stop() {
        NubrixCalendarSheet.dismiss(animated: false)
    }
}
