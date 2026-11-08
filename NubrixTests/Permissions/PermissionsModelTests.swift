import XCTest
@testable import Nubrix

@MainActor
final class PermissionsModelTests: XCTestCase {
    private let allStatuses: [PermissionStatus] = [.granted, .denied, .notDetermined, .unavailable]

    func testRowsListsEveryPermissionOnce() {
        XCTAssertEqual(PermissionsSettingsModel.rows.count, 11)
        XCTAssertEqual(Set(PermissionsSettingsModel.rows).count, 11)
    }

    func testMappingForEveryRowAndStatus() {
        for permission in PermissionsSettingsModel.rows {
            XCTAssertFalse(PermissionsSettingsModel.featureText(for: permission).isEmpty)
            for status in allStatuses {
                let action = PermissionsSettingsModel.action(for: permission, status: status)
                let text = PermissionsSettingsModel.statusText(for: permission, status: status)
                let title = PermissionsSettingsModel.buttonTitle(for: action)
                let label = "\(permission) \(status)"
                XCTAssertFalse(text.isEmpty, label)
                XCTAssertEqual(title == nil, action == .none, label)
                if status == .granted { XCTAssertEqual(action, .none, label) }
                if status == .denied { XCTAssertEqual(action, .openSettings, label) }
            }
        }
    }

    func testSpecificActions() {
        XCTAssertEqual(PermissionsSettingsModel.action(for: .pasteboard, status: .notDetermined), .openSettings)
        XCTAssertEqual(PermissionsSettingsModel.action(for: .camera, status: .notDetermined), .grant)
        XCTAssertEqual(PermissionsSettingsModel.action(for: .accessibility, status: .notDetermined), .grant)
        XCTAssertEqual(PermissionsSettingsModel.action(for: .automation(.spotify), status: .unavailable), .openSettings)
        XCTAssertEqual(PermissionsSettingsModel.action(for: .pasteboard, status: .unavailable), .openSettings)
        XCTAssertEqual(PermissionsSettingsModel.action(for: .camera, status: .unavailable), .none)
        XCTAssertEqual(PermissionsSettingsModel.action(for: .fullDiskAccess, status: .unavailable), .none)
        XCTAssertEqual(PermissionsSettingsModel.action(for: .calendar, status: .granted), .none)
    }

    func testSpecificTexts() {
        XCTAssertEqual(PermissionsSettingsModel.statusText(for: .camera, status: .granted), "Allowed")
        XCTAssertEqual(PermissionsSettingsModel.statusText(for: .camera, status: .denied), "Not allowed")
        XCTAssertEqual(PermissionsSettingsModel.statusText(for: .camera, status: .notDetermined), "Not asked yet")
        XCTAssertEqual(PermissionsSettingsModel.statusText(for: .pasteboard, status: .notDetermined), "Asks each time")
        XCTAssertEqual(PermissionsSettingsModel.statusText(for: .accessibility, status: .notDetermined), "Not allowed yet")
        XCTAssertEqual(
            PermissionsSettingsModel.statusText(for: .fullDiskAccess, status: .notDetermined),
            "Not checked (notifications from other apps are off)"
        )
        XCTAssertEqual(PermissionsSettingsModel.statusText(for: .automation(.music), status: .unavailable), "Open Music to check")
        XCTAssertEqual(PermissionsSettingsModel.statusText(for: .automation(.iterm), status: .unavailable), "Open iTerm to check")
        XCTAssertEqual(PermissionsSettingsModel.statusText(for: .fullDiskAccess, status: .unavailable), "Unknown")
        XCTAssertEqual(PermissionsSettingsModel.statusText(for: .camera, status: .unavailable), "Unavailable")
        XCTAssertEqual(PermissionsSettingsModel.buttonTitle(for: .grant), "Grant…")
        XCTAssertEqual(PermissionsSettingsModel.buttonTitle(for: .openSettings), "Open System Settings")
        XCTAssertNil(PermissionsSettingsModel.buttonTitle(for: .none))
    }

    func testRefreshFillsAllRowsWithStatusCallsOnly() async {
        let fake = FakePermissionClient(statuses: [.camera: .granted, .calendar: .denied])
        let model = PermissionsSettingsModel(client: fake)
        await model.refresh()
        XCTAssertEqual(Set(model.statuses.keys), Set(PermissionsSettingsModel.rows))
        XCTAssertEqual(model.statuses[.camera], .granted)
        XCTAssertEqual(model.statuses[.calendar], .denied)
        XCTAssertEqual(model.statuses[.pasteboard], .notDetermined)
        XCTAssertEqual(Set(fake.statusCalls), Set(PermissionsSettingsModel.rows))
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertTrue(fake.openedSettings.isEmpty)
    }

    func testPerformGrantRequestsExactlyOnce() async {
        let fake = FakePermissionClient()
        let model = PermissionsSettingsModel(client: fake)
        await model.refresh()
        await model.perform(.camera)
        XCTAssertEqual(fake.requests, [.camera])
        XCTAssertTrue(fake.openedSettings.isEmpty)
    }

    func testPerformPasteboardOpensSettingsWithoutRequest() async {
        let fake = FakePermissionClient()
        let model = PermissionsSettingsModel(client: fake)
        await model.refresh()
        await model.perform(.pasteboard)
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertEqual(fake.openedSettings, [.pasteboard])
    }

    func testPerformDeniedOpensSettings() async {
        let fake = FakePermissionClient(statuses: [.calendar: .denied])
        let model = PermissionsSettingsModel(client: fake)
        await model.refresh()
        await model.perform(.calendar)
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertEqual(fake.openedSettings, [.calendar])
    }

    func testPerformGrantedDoesNothing() async {
        let fake = FakePermissionClient(statuses: [.calendar: .granted])
        let model = PermissionsSettingsModel(client: fake)
        await model.refresh()
        await model.perform(.calendar)
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertTrue(fake.openedSettings.isEmpty)
    }
}
