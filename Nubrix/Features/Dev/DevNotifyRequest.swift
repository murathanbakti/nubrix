import Foundation

enum DevNotificationStyle: String, CaseIterable {
    case success, error, info, warning
}

struct DevNotifyRequest: Equatable {
    static let maxMessage = 500
    static let maxTitle = 80
    static let defaultDuration: Double = 4

    enum Failure: Error {
        case malformed
        case invalid
    }

    let message: String
    let title: String?
    let style: DevNotificationStyle
    let duration: Double

    static func parse(_ data: Data) -> Result<DevNotifyRequest, Failure> {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let object = any as? [String: Any]
        else { return .failure(.malformed) }

        guard let rawMessage = object["message"] as? String else { return .failure(.invalid) }
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= maxMessage else { return .failure(.invalid) }

        var title: String?
        if let raw = object["title"], !(raw is NSNull) {
            guard let text = raw as? String, text.count <= maxTitle else { return .failure(.invalid) }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            title = trimmed.isEmpty ? nil : trimmed
        }

        var style = DevNotificationStyle.info
        if let raw = object["style"], !(raw is NSNull) {
            guard let text = raw as? String, let parsed = DevNotificationStyle(rawValue: text) else {
                return .failure(.invalid)
            }
            style = parsed
        }

        var duration = defaultDuration
        if let raw = object["duration"], !(raw is NSNull) {
            guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite
            else { return .failure(.invalid) }
            duration = min(30, max(1, number.doubleValue))
        }

        return .success(DevNotifyRequest(message: message, title: title, style: style, duration: duration))
    }
}
