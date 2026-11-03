import CryptoKit
import XCTest
@testable import Nubrix

final class ClipCipherTests: XCTestCase {
    private func makeCipher() -> ClipCipher {
        ClipCipher(masterKey: ClipCipher.makeMasterKey())
    }

    private func assertThrows(_ expected: ClipCipherError, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> Void) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? ClipCipherError, expected, file: file, line: line)
        }
    }

    func testRoundTripData() throws {
        let cipher = makeCipher()
        let plain = Data((0..<1000).map { UInt8($0 % 251) })
        let sealed = try cipher.seal(plain, aad: "v1|content|abc")
        XCTAssertEqual(try cipher.open(sealed, aad: "v1|content|abc"), plain)
    }

    func testRoundTripEmptyData() throws {
        let cipher = makeCipher()
        let sealed = try cipher.seal(Data(), aad: "v1|content|abc")
        XCTAssertEqual(sealed.count, 29)
        XCTAssertEqual(try cipher.open(sealed, aad: "v1|content|abc"), Data())
    }

    func testRoundTripString() throws {
        let cipher = makeCipher()
        let text = "Çay İstanbul 👨‍👩‍👧‍👦 日本語 \u{0}end"
        let sealed = try cipher.sealString(text, aad: "v1|preview|h")
        XCTAssertEqual(try cipher.openString(sealed, aad: "v1|preview|h"), text)
        XCTAssertEqual(try cipher.openString(try cipher.sealString("", aad: "x"), aad: "x"), "")
    }

    func testSealedLayoutStartsWithVersion() throws {
        let cipher = makeCipher()
        let sealed = try cipher.seal(Data("abc".utf8), aad: "a")
        XCTAssertEqual(sealed[sealed.startIndex], ClipCipher.formatVersion)
        XCTAssertEqual(sealed.count, 1 + 12 + 3 + 16)
    }

    func testNonUTF8PlaintextFailsOpenString() throws {
        let cipher = makeCipher()
        let sealed = try cipher.seal(Data([0xff, 0xfe, 0xfd]), aad: "a")
        assertThrows(.malformed) { _ = try cipher.openString(sealed, aad: "a") }
    }

    func testTamperedByteAnywhereThrows() throws {
        let cipher = makeCipher()
        let sealed = try cipher.seal(Data("secret payload".utf8), aad: "aad")
        for index in 0..<sealed.count {
            var tampered = sealed
            tampered[tampered.startIndex + index] ^= 0x01
            XCTAssertThrowsError(try cipher.open(tampered, aad: "aad"), "byte \(index)")
        }
    }

    func testTamperedVersionNonceCiphertextAndTagReportExpectedErrors() throws {
        let cipher = makeCipher()
        let sealed = try cipher.seal(Data("secret payload".utf8), aad: "aad")

        var version = sealed
        version[0] ^= 0x01
        assertThrows(.unsupportedVersion) { _ = try cipher.open(version, aad: "aad") }

        var nonce = sealed
        nonce[1] ^= 0x80
        assertThrows(.authenticationFailed) { _ = try cipher.open(nonce, aad: "aad") }

        var body = sealed
        body[13] ^= 0x80
        assertThrows(.authenticationFailed) { _ = try cipher.open(body, aad: "aad") }

        var tag = sealed
        tag[tag.count - 1] ^= 0x80
        assertThrows(.authenticationFailed) { _ = try cipher.open(tag, aad: "aad") }
    }

    func testWrongAADThrows() throws {
        let cipher = makeCipher()
        let sealed = try cipher.seal(Data("x".utf8), aad: "v1|content|one")
        assertThrows(.authenticationFailed) { _ = try cipher.open(sealed, aad: "v1|content|two") }
        assertThrows(.authenticationFailed) { _ = try cipher.open(sealed, aad: "v1|preview|one") }
        assertThrows(.authenticationFailed) { _ = try cipher.open(sealed, aad: "") }
    }

    func testWrongKeyThrows() throws {
        let sealed = try makeCipher().seal(Data("x".utf8), aad: "a")
        assertThrows(.authenticationFailed) { _ = try makeCipher().open(sealed, aad: "a") }
    }

    func testTruncatedDataIsMalformed() throws {
        let cipher = makeCipher()
        let sealed = try cipher.seal(Data("hello".utf8), aad: "a")
        for length in 0..<29 {
            assertThrows(.malformed) { _ = try cipher.open(Data(sealed.prefix(length)), aad: "a") }
        }
        XCTAssertThrowsError(try cipher.open(Data(sealed.dropLast()), aad: "a"))
    }

    func testMinimumLengthEnvelopeIsAccepted() throws {
        let cipher = makeCipher()
        let sealed = try cipher.seal(Data(), aad: "a")
        XCTAssertEqual(try cipher.open(sealed, aad: "a"), Data())
        var wrong = sealed
        wrong[wrong.count - 1] ^= 0x01
        assertThrows(.authenticationFailed) { _ = try cipher.open(wrong, aad: "a") }
    }

    func testVersionByteTwoIsUnsupported() throws {
        let cipher = makeCipher()
        var sealed = try cipher.seal(Data("hello".utf8), aad: "a")
        sealed[0] = 2
        assertThrows(.unsupportedVersion) { _ = try cipher.open(sealed, aad: "a") }
        sealed[0] = 0
        assertThrows(.unsupportedVersion) { _ = try cipher.open(sealed, aad: "a") }
    }

    func testKeyedHashIsDeterministicPerKey() {
        let keyA = ClipCipher.makeMasterKey()
        let keyB = ClipCipher.makeMasterKey()
        let a1 = ClipCipher(masterKey: keyA)
        let a2 = ClipCipher(masterKey: keyA)
        let b = ClipCipher(masterKey: keyB)
        let data = Data("same input".utf8)
        XCTAssertEqual(a1.keyedHash(data), a2.keyedHash(data))
        XCTAssertNotEqual(a1.keyedHash(data), b.keyedHash(data))
        XCTAssertNotEqual(a1.keyedHash(data), a1.keyedHash(Data("other input".utf8)))
        XCTAssertEqual(a1.keyedHash(text: "same input"), a1.keyedHash(data))
        XCTAssertEqual(a1.keyedHash(data).count, 64)
        XCTAssertTrue(a1.keyedHash(data).allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testKeyIDIsStableForSameKeyBytesAndDiffersAcrossKeys() {
        let keyA = ClipCipher.makeMasterKey()
        let bytes = keyA.withUnsafeBytes { Data($0) }
        let first = ClipCipher(masterKey: keyA)
        let second = ClipCipher(masterKey: SymmetricKey(data: bytes))
        let other = makeCipher()
        XCTAssertEqual(first.keyID, second.keyID)
        XCTAssertNotEqual(first.keyID, other.keyID)
        XCTAssertEqual(first.keyID.count, 32)
    }

    func testCiphertextForSamePlaintextDiffers() throws {
        let cipher = makeCipher()
        let plain = Data("same plaintext".utf8)
        let one = try cipher.seal(plain, aad: "a")
        let two = try cipher.seal(plain, aad: "a")
        XCTAssertNotEqual(one, two)
        XCTAssertNotEqual(one.subdata(in: 1..<13), two.subdata(in: 1..<13))
    }

    func testSameKeyBytesDecryptAcrossInstances() throws {
        let key = ClipCipher.makeMasterKey()
        let bytes = key.withUnsafeBytes { Data($0) }
        let sealed = try ClipCipher(masterKey: key).seal(Data("persisted".utf8), aad: "a")
        XCTAssertEqual(try ClipCipher(masterKey: SymmetricKey(data: bytes)).open(sealed, aad: "a"), Data("persisted".utf8))
    }

    func testAADHelpers() {
        XCTAssertEqual(ClipCipher.fieldAAD("content", hash: "h1"), "v1|content|h1")
        XCTAssertEqual(ClipCipher.fileAAD("a.thumb.vimg"), "v1|img|a.thumb.vimg")
    }
}
