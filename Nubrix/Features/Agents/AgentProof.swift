import CryptoKit
import Foundation

enum AgentProof {
    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func bytes(fromHex text: String) -> [UInt8]? {
        let chars = Array(text.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = nibble(chars[index]), let low = nibble(chars[index + 1]) else { return nil }
            out.append(high << 4 | low)
            index += 2
        }
        return out
    }

    static func isValidNonce(_ nonce: String) -> Bool {
        nonce.utf8.count >= 16 && nonce.utf8.count <= 64 && nonce.utf8.allSatisfy { nibble($0) != nil }
    }

    static func proof(key: [UInt8], nonce: String, decision: String, sessionID: String) -> String {
        let message = Data("\(nonce)|\(decision)|\(sessionID)".utf8)
        let code = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return hex(code)
    }

    private static func nibble(_ c: UInt8) -> UInt8? {
        switch c {
        case 48...57: return c - 48
        case 97...102: return c - 87
        default: return nil
        }
    }
}
