import XCTest
@testable import Nubrix

final class EverydayAlertTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    // MARK: Sound output

    private func dev(_ uid: String, _ name: String = "X", _ transport: UInt32 = 0) -> SoundDevice {
        SoundDevice(uid: uid, name: name, transport: transport)
    }

    func testFirstReadIsIgnored() {
        var t = SoundOutputTracker()
        t.observe(dev("a"), at: at(0))
        XCTAssertNil(t.settle(at: at(5)))
    }

    func testChangeIsAnnouncedOnlyAfterOneSecond() {
        var t = SoundOutputTracker()
        t.observe(dev("a"), at: at(0))
        t.observe(dev("b"), at: at(10))
        XCTAssertNil(t.settle(at: at(10.5)))
        XCTAssertEqual(t.settle(at: at(11))?.uid, "b")
        XCTAssertNil(t.settle(at: at(12)))
    }

    func testFlappingBackToTheSameDeviceSaysNothing() {
        var t = SoundOutputTracker()
        t.observe(dev("a"), at: at(0))
        t.observe(dev("b"), at: at(10))
        t.observe(dev("a"), at: at(10.4))
        XCTAssertNil(t.settle(at: at(12)))
    }

    func testLatestDeviceWinsAndWaitRestarts() {
        var t = SoundOutputTracker()
        t.observe(dev("a"), at: at(0))
        t.observe(dev("b"), at: at(10))
        t.observe(dev("c"), at: at(10.8))
        XCTAssertNil(t.settle(at: at(11.2)))
        XCTAssertEqual(t.settle(at: at(11.8))?.uid, "c")
    }

    func testSoundSymbolsAndAlert() {
        XCTAssertEqual(dev("1", "Murat's AirPods Pro", SoundDevice.bluetooth).symbol, "airpodspro")
        XCTAssertEqual(dev("1", "AirPods Max", SoundDevice.bluetooth).symbol, "headphones")
        XCTAssertEqual(dev("1", "Sony WH", SoundDevice.bluetooth).symbol, "headphones")
        XCTAssertEqual(dev("1", "MacBook Pro Speakers", SoundDevice.builtIn).symbol, "macbook")
        XCTAssertEqual(dev("1", "DELL U2720Q", SoundDevice.displayPort).symbol, "display")
        XCTAssertEqual(dev("1", "Desk", SoundDevice.usb).symbol, "hifispeaker")
        for name in ["airpodspro", "airpods", "headphones", "macbook", "display", "hifispeaker", "externaldrive.fill",
                     "checkmark.circle.fill", "exclamationmark.triangle.fill", "mic.fill", "video.fill", "wifi", "wifi.slash"] {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
        let alert = dev("1", "Studio", SoundDevice.bluetooth).alert
        XCTAssertEqual(alert.title, "Sound plays on Studio")
        XCTAssertEqual(alert.meta, "Bluetooth")
    }

    func testFourCharacterCodes() {
        XCTAssertEqual(SoundDevice.builtIn, 0x626C746E)
        XCTAssertEqual(SoundDevice.usb, 0x75736220)
    }

    // MARK: Drives

    private func volume(path: String = "/Volumes/Backup", name: String = "Backup", internal i: Bool = false, removable: Bool = true,
                        ejectable: Bool = true, local: Bool = true, browsable: Bool = true, image: Bool = false,
                        total: Int64? = 1_000_000_000_000, free: Int64? = 250_000_000_000) -> DriveVolume {
        DriveVolume(path: path, name: name, isInternal: i, isRemovable: removable, isEjectable: ejectable, isLocal: local,
                    isBrowsable: browsable, isDiskImage: image, total: total, free: free)
    }

    func testDriveFiltering() {
        XCTAssertTrue(volume().isUserVisible)
        XCTAssertTrue(volume(internal: false, removable: false, ejectable: false).isUserVisible)
        XCTAssertTrue(volume(internal: true, removable: true, ejectable: false).isUserVisible)
        XCTAssertFalse(volume(internal: true, removable: false, ejectable: false).isUserVisible)
        XCTAssertFalse(volume(local: false).isUserVisible)
        XCTAssertFalse(volume(browsable: false).isUserVisible)
        XCTAssertFalse(volume(image: true).isUserVisible)
        XCTAssertFalse(volume(path: "/").isUserVisible)
        XCTAssertFalse(volume(path: "/System/Volumes/Data").isUserVisible)
    }

    func testDiskImageDescription() {
        XCTAssertTrue(DriveVolume.isDiskImage(protocolName: "Virtual Interface", model: nil))
        XCTAssertTrue(DriveVolume.isDiskImage(protocolName: nil, model: "Apple Disk Image"))
        XCTAssertFalse(DriveVolume.isDiskImage(protocolName: "USB", model: "SanDisk"))
    }

    func testFreeSpaceText() {
        let f = ByteCountFormatter()
        f.countStyle = .file
        XCTAssertEqual(DriveVolume.freeText(free: 250_000_000_000, total: 1_000_000_000_000),
                       "\(f.string(fromByteCount: 250_000_000_000)) free of \(f.string(fromByteCount: 1_000_000_000_000))")
        XCTAssertTrue(DriveVolume.freeText(free: 250_000_000_000, total: 1_000_000_000_000)!.contains("free of"))
        XCTAssertNil(DriveVolume.freeText(free: nil, total: 5))
        XCTAssertNil(DriveVolume.freeText(free: 5, total: 0))
    }

    func testDriveAlertsAndUnplug() {
        var t = DriveTracker()
        let v = volume()
        let alert = t.mounted(v)
        XCTAssertEqual(alert?.title, "Backup connected")
        XCTAssertEqual(alert?.action, .eject(URL(fileURLWithPath: "/Volumes/Backup")))
        XCTAssertEqual(t.unmounted(path: "/Volumes/Backup")?.title, "Backup can be unplugged")
        XCTAssertNil(t.unmounted(path: "/Volumes/Backup"))
    }

    func testHiddenVolumesAreNeverAnnounced() {
        var t = DriveTracker()
        XCTAssertNil(t.mounted(volume(image: true)))
        XCTAssertNil(t.unmounted(path: "/Volumes/Backup"))
    }

    func testSeededDrivesCanBeUnplugged() {
        var t = DriveTracker()
        t.seed([volume(), volume(path: "/Volumes/Mac", name: "Mac", internal: true, removable: false, ejectable: false)])
        XCTAssertNotNil(t.unmounted(path: "/Volumes/Backup"))
        XCTAssertNil(t.unmounted(path: "/Volumes/Mac"))
    }

    func testEjectFailureAlert() {
        let url = URL(fileURLWithPath: "/Volumes/Backup")
        let alert = DriveAlerts.ejectFailed(name: "Backup", url: url)
        XCTAssertEqual(alert.title, "Couldn't eject Backup")
        XCTAssertEqual(alert.detail, "Eject it in Finder")
        XCTAssertEqual(alert.action, .showInFinder(url))
    }

    // MARK: Microphone and camera

    func testFirstReadOnlyRecords() {
        var t = MicCameraTracker()
        XCTAssertNil(t.update(mic: true, camera: false, cameraIsOurs: false, at: at(0)))
        XCTAssertNil(t.update(mic: true, camera: false, cameraIsOurs: false, at: at(1)))
    }

    func testMicStartsThenStops() {
        var t = MicCameraTracker()
        _ = t.update(mic: false, camera: false, cameraIsOurs: false, at: at(0))
        let r = t.update(mic: true, camera: false, cameraIsOurs: false, at: at(10))
        XCTAssertEqual(r, MicCameraResult(mic: true, camera: false))
        XCTAssertEqual(r?.alert.title, "Microphone on")
        XCTAssertEqual(r?.alert.tint, .orange)
    }

    func testCameraAndBoth() {
        var t = MicCameraTracker()
        _ = t.update(mic: false, camera: false, cameraIsOurs: false, at: at(0))
        let camera = t.update(mic: false, camera: true, cameraIsOurs: false, at: at(10))
        XCTAssertEqual(camera?.alert.title, "Camera on")
        XCTAssertEqual(camera?.alert.tint, .green)

        var both = MicCameraTracker()
        _ = both.update(mic: false, camera: false, cameraIsOurs: false, at: at(0))
        let r = both.update(mic: true, camera: true, cameraIsOurs: false, at: at(10))
        XCTAssertEqual(r?.alert.title, "Camera and microphone on")
    }

    func testMicStartingWhileCameraIsOnNamesBoth() {
        var t = MicCameraTracker()
        _ = t.update(mic: false, camera: true, cameraIsOurs: false, at: at(0))
        let r = t.update(mic: true, camera: true, cameraIsOurs: false, at: at(10))
        XCTAssertEqual(r?.alert.title, "Camera and microphone on")
    }

    func testRearmsOnlyAfterFiveSeconds() {
        var t = MicCameraTracker()
        _ = t.update(mic: false, camera: false, cameraIsOurs: false, at: at(0))
        XCTAssertNotNil(t.update(mic: true, camera: false, cameraIsOurs: false, at: at(10)))
        XCTAssertNil(t.update(mic: false, camera: false, cameraIsOurs: false, at: at(20)))
        XCTAssertNil(t.update(mic: true, camera: false, cameraIsOurs: false, at: at(23)))
        XCTAssertNil(t.update(mic: false, camera: false, cameraIsOurs: false, at: at(30)))
        XCTAssertNotNil(t.update(mic: true, camera: false, cameraIsOurs: false, at: at(35)))
    }

    func testStayingOnDoesNotRepeat() {
        var t = MicCameraTracker()
        _ = t.update(mic: false, camera: false, cameraIsOurs: false, at: at(0))
        XCTAssertNotNil(t.update(mic: true, camera: false, cameraIsOurs: false, at: at(10)))
        XCTAssertNil(t.update(mic: true, camera: false, cameraIsOurs: false, at: at(60)))
    }

    func testOwnMirrorCameraIsIgnoredEvenAfterItCloses() {
        var t = MicCameraTracker()
        _ = t.update(mic: false, camera: false, cameraIsOurs: false, at: at(0))
        XCTAssertNil(t.update(mic: false, camera: true, cameraIsOurs: true, at: at(10)))
        // Mirror closed but the camera is still winding down.
        XCTAssertNil(t.update(mic: false, camera: true, cameraIsOurs: false, at: at(12)))
        XCTAssertNil(t.update(mic: false, camera: false, cameraIsOurs: false, at: at(13)))
        // Another app later.
        XCTAssertNotNil(t.update(mic: false, camera: true, cameraIsOurs: false, at: at(30)))
    }

    func testAppNames() {
        XCTAssertEqual(MicCameraTracker.cleanAppName("zoom.us Helper"), "zoom.us")
        XCTAssertEqual(MicCameraTracker.cleanAppName("Google Chrome Helper (Renderer)"), "Google Chrome")
        XCTAssertEqual(MicCameraTracker.detail(app: "Zoom"), "Used by Zoom")
        XCTAssertNil(MicCameraTracker.detail(app: nil))
        XCTAssertNil(MicCameraTracker.detail(app: ""))
    }

    // MARK: Internet

    func testOfflineNeedsThreeSeconds() {
        var t = InternetTracker()
        XCTAssertNil(t.update(satisfied: true, at: at(0)))
        XCTAssertNil(t.update(satisfied: false, at: at(10)))
        XCTAssertNil(t.settle(at: at(12)))
        XCTAssertEqual(t.settle(at: at(13)), .offline)
        XCTAssertNil(t.settle(at: at(20)))
        XCTAssertEqual(t.update(satisfied: true, at: at(30)), .backOnline)
        XCTAssertNil(t.update(satisfied: true, at: at(31)))
    }

    func testShortDropSaysNothing() {
        var t = InternetTracker()
        _ = t.update(satisfied: true, at: at(0))
        _ = t.update(satisfied: false, at: at(10))
        XCTAssertNil(t.update(satisfied: true, at: at(11)))
        XCTAssertNil(t.settle(at: at(20)))
    }

    func testNeverAlertsOnLaunch() {
        var t = InternetTracker()
        XCTAssertNil(t.update(satisfied: false, at: at(0)))
        XCTAssertNil(t.settle(at: at(10)))
        XCTAssertNil(t.update(satisfied: true, at: at(20)))
    }

    func testInternetAlerts() {
        XCTAssertEqual(InternetEvent.offline.alert.title, "You're offline")
        XCTAssertEqual(InternetEvent.offline.alert.symbol, "wifi.slash")
        XCTAssertEqual(InternetEvent.offline.alert.tint, .red)
        XCTAssertEqual(InternetEvent.backOnline.alert.title, "Back online")
        XCTAssertEqual(InternetEvent.backOnline.alert.symbol, "wifi")
        XCTAssertEqual(InternetEvent.backOnline.alert.tint, .green)
    }

    // MARK: Store

    private func alert(_ title: String) -> EverydayAlert {
        EverydayAlert(symbol: "wifi", tint: .green, title: title)
    }

    @MainActor
    func testNewerAlertReplacesOlderAndTimerRestarts() async throws {
        let store = EverydayAlertStore(duration: 0.3)
        store.show(alert("A"))
        XCTAssertEqual(store.banner?.title, "A")
        try await Task.sleep(for: .milliseconds(200))
        store.show(alert("B"))
        XCTAssertEqual(store.banner?.title, "B")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(store.banner?.title, "B", "A's timer must not dismiss B")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNil(store.banner)
    }

    @MainActor
    func testDismissClearsTheBanner() {
        let store = EverydayAlertStore(duration: 10)
        store.show(alert("A"))
        store.dismissBanner()
        XCTAssertNil(store.banner)
    }

    func testSettingsKeysDefaultOnAndAreNamed() {
        XCTAssertTrue(EverydaySource.allCases.allSatisfy { $0.key.defaultValue })
        XCTAssertEqual(EverydaySource.allCases.map(\.key.name),
                       ["everydaySoundOutput", "everydayDrives", "everydayMicCamera", "everydayInternet", "everydayScreenShare"])
    }
}
