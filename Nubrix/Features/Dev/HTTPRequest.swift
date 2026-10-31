import Foundation

struct HTTPHead {
    let method: String
    let path: String
    let headers: [String: String]
    let duplicates: Set<String>
    let contentLength: Int
    let bodyOffset: Int
}

struct HTTPRequest {
    enum Parse {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    enum HeadParse {
        case incomplete
        case invalid
        case head(HTTPHead)
    }

    static let maxHeadBytes = 16 * 1024

    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parseHead(_ data: Data) -> HeadParse {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeadBytes ? .invalid : .incomplete
        }
        guard separator.lowerBound <= maxHeadBytes,
              let head = String(data: data[data.startIndex..<separator.lowerBound], encoding: .utf8)
        else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid }

        var headers: [String: String] = [:]
        var duplicates: Set<String> = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if headers[name] != nil { duplicates.insert(name) }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        guard let length = Int(headers["content-length"] ?? "0"), length >= 0 else { return .invalid }
        return .head(HTTPHead(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            duplicates: duplicates,
            contentLength: length,
            bodyOffset: data.distance(from: data.startIndex, to: separator.upperBound)
        ))
    }

    static func parse(_ data: Data) -> Parse {
        switch parseHead(data) {
        case .incomplete: return .incomplete
        case .invalid: return .invalid
        case .head(let head):
            guard data.count - head.bodyOffset >= head.contentLength else { return .incomplete }
            let start = data.startIndex + head.bodyOffset
            let body = data.subdata(in: start..<(start + head.contentLength))
            return .complete(HTTPRequest(method: head.method, path: head.path, headers: head.headers, body: body))
        }
    }
}
