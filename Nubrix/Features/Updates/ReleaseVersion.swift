import Foundation

struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    static let maxComponentDigits = 6

    let major: Int
    let minor: Int
    let patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(tag: String) {
        let bytes = Array(tag.utf8)
        guard bytes.first == UInt8(ascii: "v"), let parts = Self.components(bytes.dropFirst()), parts.count == 3 else { return nil }
        self.init(major: parts[0], minor: parts[1], patch: parts[2])
    }

    init?(bundleVersion: String) {
        guard let parts = Self.components(Array(bundleVersion.utf8)[...]), parts.count == 2 || parts.count == 3 else { return nil }
        self.init(major: parts[0], minor: parts[1], patch: parts.count == 3 ? parts[2] : 0)
    }

    var tag: String { "v\(description)" }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    private static func components(_ bytes: ArraySlice<UInt8>) -> [Int]? {
        var result: [Int] = []
        for part in bytes.split(separator: UInt8(ascii: "."), omittingEmptySubsequences: false) {
            guard let value = number(part) else { return nil }
            result.append(value)
        }
        return result
    }

    private static func number(_ digits: ArraySlice<UInt8>) -> Int? {
        guard !digits.isEmpty, digits.count <= maxComponentDigits else { return nil }
        guard digits.allSatisfy({ $0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9") }) else { return nil }
        if digits.count > 1, digits.first == UInt8(ascii: "0") { return nil }
        return digits.reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
    }
}
