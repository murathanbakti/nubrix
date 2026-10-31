import Foundation

enum MeetingService: String, Equatable {
    case zoom
    case meet
    case teams
    case webex
    case whereby
    case slack

    var title: String {
        switch self {
        case .zoom: return "Zoom"
        case .meet: return "Google Meet"
        case .teams: return "Microsoft Teams"
        case .webex: return "Webex"
        case .whereby: return "Whereby"
        case .slack: return "Slack Huddle"
        }
    }
}

struct MeetingLink: Equatable {
    let service: MeetingService
    let webURL: URL
    let nativeURL: URL?
}

enum MeetingLinkDetector {
    private static let tail = #"[^\s"'<>\\]*"#

    private static let rules: [(MeetingService, NSRegularExpression)] = {
        let patterns: [(MeetingService, String)] = [
            (.zoom, #"https?://(?:[A-Za-z0-9-]+\.)*zoom(?:gov)?\.(?:us|com)/(?:j|my|wc/join)/"# + tail),
            (.zoom, #"zoommtg://"# + tail),
            (.meet, #"https://meet\.google\.com/(?:[a-z]{3}-[a-z]{4}-[a-z]{3}|lookup/[A-Za-z0-9_-]+)(?:\?[A-Za-z0-9=%_.-]+)?"#),
            (.teams, #"https://teams\.microsoft\.com/l/meetup-join/"# + tail),
            (.teams, #"https://teams\.live\.com/meet/"# + tail),
            (.webex, #"https://(?:[A-Za-z0-9-]+\.)*webex\.com/(?:meet|join|wbxmjs|[A-Za-z0-9._-]+/j\.php)"# + tail),
            (.whereby, #"https://whereby\.com/[A-Za-z0-9_-]+"# + tail),
            (.slack, #"https://app\.slack\.com/huddle/[A-Za-z0-9]+/[A-Za-z0-9]+"#),
        ]
        return patterns.compactMap { service, pattern in
            (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map { (service, $0) }
        }
    }()

    static func detect(url: URL?, location: String?, notes: String?) -> MeetingLink? {
        let sources = [url?.absoluteString, location, notes]
        for source in sources {
            guard let source, !source.isEmpty else { continue }
            if let link = detect(in: source) { return link }
        }
        return nil
    }

    static func detect(in text: String) -> MeetingLink? {
        let cleaned = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\u0026", with: "&")
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        var best: (service: MeetingService, raw: String, location: Int)?
        for (service, regex) in rules {
            guard let match = regex.firstMatch(in: cleaned, options: [], range: range),
                  let swiftRange = Range(match.range, in: cleaned) else { continue }
            if best == nil || match.range.location < best!.location {
                best = (service, String(cleaned[swiftRange]), match.range.location)
            }
        }
        guard let best else { return nil }
        let raw = trim(best.raw)
        guard let web = URL(string: raw) else { return nil }
        return MeetingLink(service: best.service, webURL: web, nativeURL: nativeURL(service: best.service, url: web))
    }

    private static func trim(_ raw: String) -> String {
        var value = raw
        for marker in ["&sa=", "&usg=", "&ust="] {
            if let range = value.range(of: marker) { value = String(value[..<range.lowerBound]) }
        }
        while let last = value.last, ".,;:)]}>'\"".contains(last) { value.removeLast() }
        return value
    }

    static func nativeURL(service: MeetingService, url: URL) -> URL? {
        switch service {
        case .zoom:
            if url.scheme == "zoommtg" { return nil }
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let host = components.host else { return nil }
            let parts = components.path.split(separator: "/").map(String.init)
            guard parts.count >= 2, parts[0] == "j" || parts[0] == "wc",
                  let id = parts.last(where: { $0.allSatisfy(\.isNumber) }) else { return nil }
            var items = [URLQueryItem(name: "confno", value: id)]
            if let pwd = components.queryItems?.first(where: { $0.name == "pwd" })?.value {
                items.append(URLQueryItem(name: "pwd", value: pwd))
            }
            var native = URLComponents()
            native.scheme = "zoommtg"
            native.host = host
            native.path = "/join"
            native.queryItems = items
            return native.url
        case .teams:
            guard url.host == "teams.microsoft.com" else { return nil }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "msteams"
            return components?.url
        case .meet, .webex, .whereby, .slack:
            return nil
        }
    }
}

struct MeetingCandidate: Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let isDeclined: Bool
}

enum MeetingSelector {
    static let ongoingGrace: TimeInterval = 600

    static func pick(
        from events: [MeetingCandidate],
        now: Date,
        leadMinutes: Int,
        dismissed: Set<String>
    ) -> MeetingCandidate? {
        let lead = TimeInterval(max(1, leadMinutes) * 60)
        let eligible = events.filter { event in
            guard !event.isAllDay, !event.isDeclined, !dismissed.contains(event.id), event.end > now else {
                return false
            }
            if event.start > now { return event.start.timeIntervalSince(now) <= lead }
            return now.timeIntervalSince(event.start) < ongoingGrace
        }
        return eligible.min { lhs, rhs in
            let l = abs(lhs.start.timeIntervalSince(now))
            let r = abs(rhs.start.timeIntervalSince(now))
            if l != r { return l < r }
            return lhs.start < rhs.start
        }
    }
}

enum MeetingBannerKind: String, Equatable {
    case lead
    case imminent
}

enum MeetingBannerPlanner {
    static func due(
        secondsUntil: TimeInterval,
        leadMinutes: Int,
        oneMinuteEnabled: Bool,
        fired: Set<MeetingBannerKind>
    ) -> MeetingBannerKind? {
        let window: TimeInterval = 90
        guard secondsUntil > 0 else { return nil }
        let leadSeconds = TimeInterval(max(1, leadMinutes) * 60)
        if oneMinuteEnabled, leadMinutes > 1, !fired.contains(.imminent),
           secondsUntil <= 60, secondsUntil > 60 - window {
            return .imminent
        }
        if !fired.contains(.lead), secondsUntil <= leadSeconds, secondsUntil > leadSeconds - window {
            return .lead
        }
        return nil
    }
}

enum MeetingCountdown {
    static func minutes(until start: Date, now: Date) -> Int {
        let seconds = start.timeIntervalSince(now)
        guard seconds > 0 else { return 0 }
        return Int((seconds / 60).rounded(.up))
    }

    static func isUrgent(until start: Date, now: Date) -> Bool {
        let seconds = start.timeIntervalSince(now)
        return seconds > 0 && minutes(until: start, now: now) <= 1
    }

    static func hasStarted(_ start: Date, now: Date) -> Bool {
        start <= now
    }

    static func nowWord(locale: Locale) -> String {
        switch locale.language.languageCode?.identifier {
        case "tr": return "Şimdi"
        case "de": return "Jetzt"
        case "es": return "Ahora"
        default: return "Now"
        }
    }

    static func label(until start: Date, now: Date, locale: Locale) -> String {
        guard start > now else { return nowWord(locale: locale) }
        return duration(minutes: minutes(until: start, now: now), locale: locale)
    }

    static func duration(minutes: Int, locale: Locale) -> String {
        let value = max(0, minutes)
        if locale.language.languageCode?.identifier == "tr" {
            if value >= 60 {
                let hours = value / 60
                let rest = value % 60
                return rest == 0 ? "\(hours) sa" : "\(hours) sa \(rest) dk"
            }
            return "\(value) dk"
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = value >= 60 ? [.hour, .minute] : [.minute]
        formatter.zeroFormattingBehavior = .dropAll
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        return formatter.string(from: TimeInterval(value * 60)) ?? "\(value)m"
    }
}

enum MeetingText {
    private static func isTurkish(_ locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "tr"
    }

    static func join(_ locale: Locale) -> String { isTurkish(locale) ? "Katıl" : "Join" }
    static func dismiss(_ locale: Locale) -> String { isTurkish(locale) ? "Gizle" : "Dismiss" }
    static func attendees(_ count: Int, locale: Locale) -> String {
        isTurkish(locale) ? "\(count) kişi" : (count == 1 ? "1 person" : "\(count) people")
    }
}
