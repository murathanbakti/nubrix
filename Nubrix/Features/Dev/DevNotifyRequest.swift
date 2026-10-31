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

    private static func flattened(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    static func parse(_ data: Data) -> Result<DevNotifyRequest, Failure> {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let object = any as? [String: Any]
        else { return .failure(.malformed) }

        guard let rawMessage = object["message"] as? String else { return .failure(.invalid) }
        guard rawMessage.count <= maxMessage else { return .failure(.invalid) }
        let message = AgentText.sanitized(flattened(rawMessage), limit: maxMessage)
        guard !message.isEmpty else { return .failure(.invalid) }

        var title: String?
        if let raw = object["title"], !(raw is NSNull) {
            guard let text = raw as? String, text.count <= maxTitle else { return .failure(.invalid) }
            let trimmed = AgentText.sanitized(flattened(text), limit: maxTitle)
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
