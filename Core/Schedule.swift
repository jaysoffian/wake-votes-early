import Foundation

/// Early-voting hours for a given election period.
public struct EarlyVotingSchedule: Sendable {
    public struct Hours: Sendable, Hashable {
        public let open: Date
        public let close: Date
    }

    public let timeZone: TimeZone
    public let firstDay: DateComponents
    public let lastDay: DateComponents

    public init(timeZone: TimeZone, firstDay: DateComponents, lastDay: DateComponents) {
        self.timeZone = timeZone
        self.firstDay = firstDay
        self.lastDay = lastDay
    }

    /// Wake County, 2026 general election: Oct 15–31.
    /// Weekdays 8:00–19:30, Saturdays 8:00–15:00, Sundays 13:00–18:00.
    public static let wake2026General = EarlyVotingSchedule(
        timeZone: TimeZone(identifier: "America/New_York")!,
        firstDay: DateComponents(year: 2026, month: 10, day: 15),
        lastDay: DateComponents(year: 2026, month: 10, day: 31)
    )

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal
    }

    /// Hours on the calendar day containing `date`, or nil if that day has no early voting.
    public func hours(on date: Date) -> Hours? {
        let cal = calendar
        guard let first = cal.date(from: firstDay), let last = cal.date(from: lastDay) else { return nil }
        let day = cal.startOfDay(for: date)
        guard day >= cal.startOfDay(for: first), day <= cal.startOfDay(for: last) else { return nil }
        let (openH, openM, closeH, closeM): (Int, Int, Int, Int)
        switch cal.component(.weekday, from: day) {
        case 1: (openH, openM, closeH, closeM) = (13, 0, 18, 0)   // Sunday
        case 7: (openH, openM, closeH, closeM) = (8, 0, 15, 0)    // Saturday
        default: (openH, openM, closeH, closeM) = (8, 0, 19, 30)  // Weekdays
        }
        guard let open = cal.date(bySettingHour: openH, minute: openM, second: 0, of: day),
              let close = cal.date(bySettingHour: closeH, minute: closeM, second: 0, of: day) else { return nil }
        return Hours(open: open, close: close)
    }

    /// The next day with early voting at or after `date`, if any.
    public func nextOpening(after date: Date) -> Hours? {
        let cal = calendar
        var day = cal.startOfDay(for: date)
        for _ in 0..<60 {
            if let h = hours(on: day), h.open > date { return h }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return nil
    }
}
