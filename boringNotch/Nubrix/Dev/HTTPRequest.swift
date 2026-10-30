import Foundation

struct HTTPRequest {
    enum Parse {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> Parse {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 16 * 1024 ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<separator.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        guard let length = Int(headers["content-length"] ?? "0"), length >= 0 else { return .invalid }
        let bodyStart = separator.upperBound
        guard data.count - bodyStart >= length else { return .incomplete }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        return .complete(HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers, body: body))
    }
}
