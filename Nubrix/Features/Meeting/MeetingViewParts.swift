import SwiftUI

enum MeetingTint {
    static let urgent = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let started = Color(red: 0.2, green: 0.84, blue: 0.4)
    static let normal = Color.white

    static func countdown(start: Date, now: Date) -> Color {
        if MeetingCountdown.hasStarted(start, now: now) { return started }
        return MeetingCountdown.isUrgent(until: start, now: now) ? urgent : normal
    }
}

extension MeetingService {
    var symbol: String {
        switch self {
        case .zoom, .meet, .teams, .webex, .whereby: return "video.fill"
        case .slack: return "headphones"
        }
    }
}

enum MeetingWing {
    static func width(closedHeight: CGFloat) -> CGFloat {
        max(max(0, closedHeight - 12), 38)
    }

    static func extraWidth(closedHeight: CGFloat) -> CGFloat {
        2 * width(closedHeight: closedHeight)
    }
}

struct MeetingGlyph: View {
    let meeting: MeetingInfo
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let link = meeting.link {
                Image(systemName: link.service.symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(meeting.color)
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(meeting.color)
                    .frame(width: size * 0.6, height: size * 0.6)
                    .frame(width: size, height: size)
            }
        }
    }
}

struct MeetingWingContent: View {
    let meeting: MeetingInfo
    let now: Date
    let closedHeight: CGFloat
    let notchGap: CGFloat
    @Environment(\.locale) private var locale

    var body: some View {
        let side = max(0, closedHeight - 12)
        let wing = MeetingWing.width(closedHeight: closedHeight)
        HStack {
            MeetingGlyph(meeting: meeting, size: side * 0.8)
                .frame(width: wing, height: side)
            Rectangle()
                .fill(.black)
                .frame(width: notchGap)
            Text(MeetingCountdown.label(until: meeting.start, now: now, locale: locale))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(MeetingTint.countdown(start: meeting.start, now: now))
                .frame(width: wing, height: side)
        }
        .frame(height: closedHeight, alignment: .center)
    }
}

struct MeetingBannerContent: View {
    let banner: MeetingBanner
    let meeting: MeetingInfo?
    let closedHeight: CGFloat
    let notchGap: CGFloat
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if let meeting {
                    MeetingGlyph(meeting: meeting, size: 14)
                } else {
                    Image(systemName: "calendar")
                        .foregroundStyle(.white)
                }
                Text(banner.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 220, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: notchGap)

            Text(MeetingCountdown.duration(minutes: banner.minutes, locale: locale))
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(banner.minutes <= 1 ? MeetingTint.urgent : Color.white)
                .lineLimit(1)
                .frame(width: 90, alignment: .trailing)
        }
        .frame(height: closedHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(banner.title) · \(MeetingCountdown.duration(minutes: banner.minutes, locale: locale))")
    }
}

struct MeetingCardContent: View {
    let meeting: MeetingInfo
    let now: Date
    let onJoin: () -> Void
    let onDismiss: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(meeting.color).frame(width: 8, height: 8)
                Text(MeetingCountdown.label(until: meeting.start, now: now, locale: locale))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MeetingTint.countdown(start: meeting.start, now: now))
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.gray)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(MeetingText.dismiss(locale))
                .accessibilityLabel(MeetingText.dismiss(locale))
            }

            Text(meeting.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(Self.range(meeting.start, meeting.end, locale: locale))
                    .monospacedDigit()
                if meeting.attendeeCount > 1 {
                    Label(String(meeting.attendeeCount), systemImage: "person.2.fill")
                        .labelStyle(.titleAndIcon)
                        .help(MeetingText.attendees(meeting.attendeeCount, locale: locale))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.gray)
            .lineLimit(1)

            Spacer(minLength: 0)

            if let link = meeting.link {
                Button(action: onJoin) {
                    HStack(spacing: 5) {
                        Image(systemName: link.service.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(MeetingText.join(locale))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.accentColor))
                }
                .buttonStyle(.plain)
                .help(link.service.title)
            }
        }
        .padding(10)
        .frame(width: 168, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
    }

    static func range(_ start: Date, _ end: Date, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}
