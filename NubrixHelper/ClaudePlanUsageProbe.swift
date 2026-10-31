import Foundation
import Darwin

struct ProbeLimit: Codable, Equatable {
    var kind: String
    var group: String
    var percent: Double
    var resetsAt: Double?
    var isActive: Bool
    var severity: String
    var scopeModel: String?
}

enum ProbeError: String, Codable {
    case notInstalled
    case notSubscriber
    case timeout
    case failed
    case unsupported
}

struct ProbeResult: Codable, Equatable {
    var limits: [ProbeLimit]?
    var fetchedAt: Double?
    var error: ProbeError?

    static func failure(_ error: ProbeError) -> ProbeResult {
        ProbeResult(limits: nil, fetchedAt: nil, error: error)
    }

    func encoded() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data(#"{"error":"failed"}"#.utf8)
    }
}

enum ClaudeExecutableLocator {
    static func realHome() -> String? {
        guard let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir else { return nil }
        let path = String(cString: dir)
        return path.hasPrefix("/") ? path : nil
    }

    static func candidates(home: String) -> [String] {
        [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            home + "/.local/bin/claude",
            home + "/.claude/local/claude"
        ]
    }

    static func locate(home: String? = realHome(), uid: uid_t = getuid()) -> URL? {
        guard let home else { return nil }
        for path in candidates(home: home) {
            if let url = validated(path, uid: uid) { return url }
        }
        return nil
    }

    static func validated(_ path: String, uid: uid_t = getuid()) -> URL? {
        var entry = stat()
        guard lstat(path, &entry) == 0 else { return nil }
        let isLink = (entry.st_mode & S_IFMT) == S_IFLNK
        guard trustedOwner(entry, uid: uid) else { return nil }
        if !isLink, !acceptableFile(entry, uid: uid) { return nil }

        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        let target = String(cString: resolved)

        var info = stat()
        guard stat(target, &info) == 0, acceptableFile(info, uid: uid), access(target, X_OK) == 0 else { return nil }

        let parent = (target as NSString).deletingLastPathComponent
        var parentInfo = stat()
        guard stat(parent, &parentInfo) == 0,
              (parentInfo.st_mode & S_IFMT) == S_IFDIR,
              trustedOwner(parentInfo, uid: uid),
              (parentInfo.st_mode & S_IWOTH) == 0 else { return nil }
        return URL(fileURLWithPath: target)
    }

    private static func trustedOwner(_ info: stat, uid: uid_t) -> Bool {
        info.st_uid == uid || info.st_uid == 0
    }

    private static func acceptableFile(_ info: stat, uid: uid_t) -> Bool {
        (info.st_mode & S_IFMT) == S_IFREG
            && trustedOwner(info, uid: uid)
            && (info.st_mode & (S_IWGRP | S_IWOTH)) == 0
            && (info.st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0
    }
}

enum ClaudePlanUsageParser {
    static let maxLimits = 16

    static func parse(_ data: Data, now: Date = Date()) -> ProbeResult {
        var found = false
        var result = ProbeResult.failure(.failed)
        let marker = Data("usage_report".utf8)
        for slice in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard slice.first == 0x7B, slice.range(of: marker) != nil else { continue }
            guard let object = (try? JSONSerialization.jsonObject(with: Data(slice))) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let report = object["usage_report"] as? [String: Any] else { continue }
            found = true
            result = interpret(report, now: now)
        }
        return found ? result : .failure(.failed)
    }

    private static func interpret(_ report: [String: Any], now: Date) -> ProbeResult {
        guard let rate = report["rate_limits"] as? [String: Any] else {
            return .failure(.notSubscriber)
        }
        guard let raw = rate["limits"] as? [Any] else { return .failure(.notSubscriber) }
        var limits: [ProbeLimit] = []
        for item in raw.prefix(maxLimits) {
            guard let entry = item as? [String: Any], let limit = limit(entry) else { continue }
            limits.append(limit)
        }
        guard !limits.isEmpty else { return .failure(.notSubscriber) }
        return ProbeResult(limits: limits, fetchedAt: now.timeIntervalSince1970, error: nil)
    }

    private static func limit(_ entry: [String: Any]) -> ProbeLimit? {
        let kind = token(entry["kind"], limit: 32)
        guard !kind.isEmpty, let number = entry["percent"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let percent = number.doubleValue
        guard percent.isFinite else { return nil }
        var scopeModel: String?
        if let scope = entry["scope"] as? [String: Any], let model = scope["model"] as? [String: Any] {
            let name = label(model["display_name"], limit: 40)
            scopeModel = name.isEmpty ? nil : name
        }
        return ProbeLimit(
            kind: kind,
            group: token(entry["group"], limit: 32),
            percent: min(100, max(0, percent)),
            resetsAt: (entry["resets_at"] as? String).flatMap(date)?.timeIntervalSince1970,
            isActive: (entry["is_active"] as? Bool) ?? false,
            severity: token(entry["severity"], limit: 32),
            scopeModel: scopeModel)
    }

    static func date(_ text: String) -> Date? {
        guard text.utf8.count <= 40 else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = fractional.date(from: text) { return value }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    private static let tokenScalars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")

    private static func token(_ value: Any?, limit: Int) -> String {
        guard let text = value as? String else { return "" }
        return String(String.UnicodeScalarView(text.unicodeScalars.filter { tokenScalars.contains($0) }.prefix(limit)))
    }

    private static func label(_ value: Any?, limit: Int) -> String {
        guard let text = value as? String else { return "" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-+"))
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.filter { allowed.contains($0) }.prefix(limit)))
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}

struct ProbeExecution {
    var data = Data()
    var launched = false
    var timedOut = false
    var overflowed = false
    var unsupported = false
}

struct ProbeStreamInspector {
    static let maxLine = 512 * 1024
    private static let reportMarker = Data("usage_report".utf8)

    private var pending = Data()
    private var skipping = false
    private(set) var unsupported = false

    mutating func feed(_ chunk: Data) -> Bool {
        guard !unsupported else { return false }
        var rest = chunk[...]
        while let newline = rest.firstIndex(of: 0x0A) {
            let head = rest[rest.startIndex..<newline]
            rest = rest[rest.index(after: newline)...]
            if skipping {
                skipping = false
            } else {
                pending.append(contentsOf: head)
                let line = pending
                pending.removeAll(keepingCapacity: true)
                if inspect(line) { return true }
            }
        }
        if !skipping {
            pending.append(contentsOf: rest)
            if pending.count > Self.maxLine {
                pending.removeAll(keepingCapacity: false)
                skipping = true
            }
        }
        return false
    }

    private mutating func inspect(_ line: Data) -> Bool {
        guard line.first == 0x7B, line.count <= Self.maxLine,
              line.range(of: Self.reportMarker) == nil,
              let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = object["type"] as? String else { return false }
        switch type {
        case "system":
            guard object["subtype"] as? String == "init" else { return false }
            let commands = object["slash_commands"] as? [Any] ?? []
            if !commands.contains(where: { ($0 as? String) == "usage" }) { unsupported = true }
        case "result":
            if let cost = object["total_cost_usd"] as? NSNumber, cost.doubleValue > 0 { unsupported = true }
            if let turns = object["num_turns"] as? NSNumber, turns.intValue > 0 { unsupported = true }
        default:
            break
        }
        return unsupported
    }
}

enum ClaudePlanUsageProbe {
    static let arguments = [
        "-p", "--output-format", "stream-json", "--verbose", "--setting-sources", "project",
        "--tools", "", "--strict-mcp-config", "--no-session-persistence", "/usage"
    ]
    static let timeout: TimeInterval = 30
    static let outputCap = 1_048_576
    static let searchPath = "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"

    private static let gate = NSLock()
    private static var running = false

    static func fetch() -> ProbeResult {
        gate.lock()
        if running {
            gate.unlock()
            return .failure(.failed)
        }
        running = true
        gate.unlock()
        defer {
            gate.lock()
            running = false
            gate.unlock()
        }

        guard let home = ClaudeExecutableLocator.realHome() else { return .failure(.notInstalled) }
        LegacyTranscriptCleaner.runOnce(home: home)
        guard let executable = ClaudeExecutableLocator.locate(home: home) else {
            return .failure(.notInstalled)
        }
        guard let directory = makeScratchDirectory() else { return .failure(.failed) }
        defer { try? FileManager.default.removeItem(at: directory) }

        let environment = [
            "HOME": home,
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "PATH": searchPath,
            "LANG": "en_US.UTF-8"
        ]
        let run = execute(executable: executable, arguments: arguments, environment: environment,
                          directory: directory, timeout: timeout, cap: outputCap)
        guard run.launched else { return .failure(.failed) }
        if run.unsupported { return .failure(.unsupported) }
        let parsed = ClaudePlanUsageParser.parse(run.data)
        if parsed.error == nil { return parsed }
        if run.timedOut { return .failure(.timeout) }
        return parsed
    }

    static func makeScratchDirectory() -> URL? {
        var template = Array((NSTemporaryDirectory() as NSString).appendingPathComponent("nubrix-usage-XXXXXX").utf8CString)
        guard mkdtemp(&template) != nil else { return nil }
        return URL(fileURLWithPath: String(cString: template), isDirectory: true)
    }

    static func execute(executable: URL, arguments: [String], environment: [String: String],
                        directory: URL, timeout: TimeInterval, cap: Int) -> ProbeExecution {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.qualityOfService = .utility
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        let pipe = Pipe()
        process.standardOutput = pipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        var execution = ProbeExecution()
        do {
            try process.run()
        } catch {
            return execution
        }
        execution.launched = true
        let pid = process.processIdentifier

        let box = OutputBox(cap: cap)
        let readerDone = DispatchSemaphore(value: 0)
        let reader = pipe.fileHandleForReading
        let thread = Thread {
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                switch box.append(chunk) {
                case .continue: break
                case .overflow: kill(pid, SIGTERM)
                case .unsupported: kill(pid, SIGKILL)
                }
            }
            readerDone.signal()
        }
        thread.start()

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            execution.timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(pid, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
        }
        if readerDone.wait(timeout: .now() + 2) == .timedOut {
            try? reader.close()
        }
        let snapshot = box.snapshot()
        execution.data = snapshot.data
        execution.overflowed = snapshot.overflowed
        execution.unsupported = snapshot.unsupported
        return execution
    }
}

private enum OutputAction {
    case `continue`
    case overflow
    case unsupported
}

private final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private let cap: Int
    private var data = Data()
    private var overflowed = false
    private var inspector = ProbeStreamInspector()

    init(cap: Int) { self.cap = cap }

    func append(_ chunk: Data) -> OutputAction {
        lock.lock()
        defer { lock.unlock() }
        guard !overflowed else { return .continue }
        let room = cap - data.count
        let wasUnsupported = inspector.unsupported
        if chunk.count > room {
            data.append(chunk.prefix(max(0, room)))
            overflowed = true
            _ = inspector.feed(chunk.prefix(max(0, room)))
            return inspector.unsupported ? .unsupported : .overflow
        }
        data.append(chunk)
        if inspector.feed(chunk), !wasUnsupported { return .unsupported }
        return .continue
    }

    func snapshot() -> (data: Data, overflowed: Bool, unsupported: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (data, overflowed, inspector.unsupported)
    }
}

enum LegacyTranscriptCleaner {
    private static let lock = NSLock()
    private static var done = false

    static func runOnce(home: String) {
        lock.lock()
        let already = done
        done = true
        lock.unlock()
        if already { return }
        clean(projects: home + "/.claude/projects", uid: getuid())
    }

    static func matches(_ name: String) -> Bool {
        let marker = "-T-nubrix-usage-"
        guard name.hasPrefix("-private-var-folders-"),
              let range = name.range(of: marker, options: .backwards) else { return false }
        let suffix = name[range.upperBound...]
        return suffix.count == 6 && suffix.unicodeScalars.allSatisfy {
            ($0.value < 128) && CharacterSet.alphanumerics.contains($0)
        }
    }

    static func clean(projects: String, uid: uid_t) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: projects) else { return }
        for name in names where matches(name) {
            let path = projects + "/" + name
            var entry = stat()
            guard lstat(path, &entry) == 0,
                  (entry.st_mode & S_IFMT) == S_IFDIR,
                  entry.st_uid == uid else { continue }
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}
