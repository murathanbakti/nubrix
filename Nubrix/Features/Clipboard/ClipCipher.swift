import CryptoKit
import Foundation

enum ClipCipherError: Error {
    case malformed
    case unsupportedVersion
    case authenticationFailed
}

struct ClipCipher: @unchecked Sendable {
    static let formatVersion: UInt8 = 1

    private static let nonceLength = 12
    private static let tagLength = 16

    let keyID: String

    private let enc: SymmetricKey
    private let mac: SymmetricKey

    static func makeMasterKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func fieldAAD(_ column: String, hash: String) -> String {
        "v1|\(column)|\(hash)"
    }

    static func fileAAD(_ name: String) -> String {
        "v1|img|\(name)"
    }

    init(masterKey: SymmetricKey) {
        let enc = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: Data(),
            info: Data("nubrix.vitrin.enc.v1".utf8),
            outputByteCount: 32
        )
        let mac = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: masterKey,
            salt: Data(),
            info: Data("nubrix.vitrin.mac.v1".utf8),
            outputByteCount: 32
        )
        self.enc = enc
        self.mac = mac
        let tag = HMAC<SHA256>.authenticationCode(for: Data("key-id".utf8), using: mac)
        self.keyID = Self.hex(Array(tag.prefix(16)))
    }

    func seal(_ plaintext: Data, aad: String) throws -> Data {
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.seal(plaintext, using: enc, authenticating: Data(aad.utf8))
        } catch {
            throw ClipCipherError.malformed
        }
        guard let combined = box.combined else { throw ClipCipherError.malformed }
        var out = Data([Self.formatVersion])
        out.append(combined)
        return out
    }

    func open(_ sealed: Data, aad: String) throws -> Data {
        guard sealed.count >= 1 + Self.nonceLength + Self.tagLength else { throw ClipCipherError.malformed }
        guard sealed[sealed.startIndex] == Self.formatVersion else { throw ClipCipherError.unsupportedVersion }
        let box: AES.GCM.SealedBox
        do {
            box = try AES.GCM.SealedBox(combined: Data(sealed.dropFirst()))
        } catch {
            throw ClipCipherError.malformed
        }
        do {
            return try AES.GCM.open(box, using: enc, authenticating: Data(aad.utf8))
        } catch {
            throw ClipCipherError.authenticationFailed
        }
    }

    func sealString(_ s: String, aad: String) throws -> Data {
        try seal(Data(s.utf8), aad: aad)
    }

    func openString(_ d: Data, aad: String) throws -> String {
        let plain = try open(d, aad: aad)
        guard let s = String(data: plain, encoding: .utf8) else { throw ClipCipherError.malformed }
        return s
    }

    func keyedHash(_ data: Data) -> String {
        Self.hex(Array(HMAC<SHA256>.authenticationCode(for: data, using: mac)))
    }

    func keyedHash(text: String) -> String {
        keyedHash(Data(text.utf8))
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}
