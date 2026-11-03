import XCTest
@testable import Nubrix

final class UpdateInstallKindTests: XCTestCase {
    private let release = "399MAAJ7QT"

    func testReleaseTeamIdentifierConstant() {
        XCTAssertEqual(UpdateInstallKind.releaseTeamIdentifier, release)
    }

    func testNilTeamIsSourceBuild() {
        XCTAssertEqual(UpdateInstallKind.resolve(teamIdentifier: nil, isHomebrew: false), .sourceBuild)
        XCTAssertEqual(UpdateInstallKind.resolve(teamIdentifier: nil, isHomebrew: true), .sourceBuild)
    }

    func testOtherTeamIsSourceBuildEvenWithHomebrew() {
        XCTAssertEqual(UpdateInstallKind.resolve(teamIdentifier: "ABCDE12345", isHomebrew: true), .sourceBuild)
        XCTAssertEqual(UpdateInstallKind.resolve(teamIdentifier: "ABCDE12345", isHomebrew: false), .sourceBuild)
    }

    func testLookalikeTeamIsSourceBuild() {
        XCTAssertEqual(UpdateInstallKind.resolve(teamIdentifier: "399maaj7qt", isHomebrew: false), .sourceBuild)
        XCTAssertEqual(UpdateInstallKind.resolve(teamIdentifier: "", isHomebrew: false), .sourceBuild)
    }

    func testReleaseTeamWithHomebrew() {
        XCTAssertEqual(UpdateInstallKind.resolve(teamIdentifier: release, isHomebrew: true), .homebrew)
    }

    func testReleaseTeamWithoutHomebrew() {
        XCTAssertEqual(UpdateInstallKind.resolve(teamIdentifier: release, isHomebrew: false), .releaseZip)
    }

    func testHomebrewInstructions() {
        let instructions = UpdateInstallKind.homebrew.instructions
        XCTAssertEqual(instructions.summary, "Installed with Homebrew. Update in Terminal:")
        XCTAssertEqual(instructions.command, "brew upgrade --cask nubrix")
        XCTAssertTrue(instructions.showsViewRelease)
        XCTAssertTrue(instructions.hooksReminder.contains("After updating, run install-hooks.sh again so the sealed hook copies match the new version, then reopen Nubrix"))
        XCTAssertTrue(instructions.hooksReminder.contains("bash /Applications/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh"))
    }

    func testReleaseZipInstructions() {
        let instructions = UpdateInstallKind.releaseZip.instructions
        XCTAssertEqual(instructions.summary, "Download it from the release page, or run the install script again:")
        XCTAssertEqual(instructions.command, "curl -fsSL https://raw.githubusercontent.com/murathanbakti/nubrix/main/scripts/install.sh | bash")
        XCTAssertTrue(instructions.showsViewRelease)
        XCTAssertTrue(instructions.hooksReminder.contains("After updating, run install-hooks.sh again"))
        XCTAssertTrue(instructions.hooksReminder.contains("bash /Applications/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh"))
    }

    func testSourceBuildInstructions() {
        let instructions = UpdateInstallKind.sourceBuild.instructions
        XCTAssertEqual(instructions.summary, "Built from source. In your checkout:")
        XCTAssertEqual(instructions.command, "git pull && scripts/install-local.sh")
        XCTAssertTrue(instructions.showsViewRelease)
        XCTAssertTrue(instructions.hooksReminder.contains("install-local.sh"))
        XCTAssertFalse(instructions.hooksReminder.contains("/Applications/Nubrix.app"))
    }

    func testReleaseURLUsesValidatedTag() {
        let url = UpdateLinks.releaseURL(for: ReleaseVersion(major: 0, minor: 1, patch: 1))
        XCTAssertEqual(url.absoluteString, "https://github.com/murathanbakti/nubrix/releases/tag/v0.1.1")
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
    }

    func testReleaseURLForParsedTagMatches() throws {
        let version = try XCTUnwrap(ReleaseVersion(tag: "v12.34.56"))
        XCTAssertEqual(UpdateLinks.releaseURL(for: version).absoluteString, "https://github.com/murathanbakti/nubrix/releases/tag/v12.34.56")
    }

    func testLatestReleaseAPIConstant() {
        XCTAssertEqual(UpdateLinks.latestReleaseAPI.absoluteString, "https://api.github.com/repos/murathanbakti/nubrix/releases/latest")
    }
}
