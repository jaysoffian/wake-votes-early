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
    /// Election Day itself (polls at assigned precincts, not early-voting sites).
    public let electionDay: DateComponents
    public let electionDayOpen: (hour: Int, minute: Int)
    public let electionDayClose: (hour: Int, minute: Int)

    public init(timeZone: TimeZone, firstDay: DateComponents, lastDay: DateComponents,
                electionDay: DateComponents, electionDayOpen: (Int, Int), electionDayClose: (Int, Int)) {
        self.timeZone = timeZone
        self.firstDay = firstDay
        self.lastDay = lastDay
        self.electionDay = electionDay
        self.electionDayOpen = electionDayOpen
        self.electionDayClose = electionDayClose
    }

    /// Wake County, 2026 general election: early voting Oct 15–31
    /// (weekdays 8:00–19:30, Saturdays 8:00–15:00, Sundays 13:00–18:00); Election Day Nov 3, 6:30–19:30.
    public static let wake2026General = EarlyVotingSchedule(
        timeZone: TimeZone(identifier: "America/New_York")!,
        firstDay: DateComponents(year: 2026, month: 10, day: 15),
        lastDay: DateComponents(year: 2026, month: 10, day: 31),
        electionDay: DateComponents(year: 2026, month: 11, day: 3),
        electionDayOpen: (6, 30),
        electionDayClose: (19, 30)
    )

    /// Election Day polling hours, for the "early voting has ended" screen.
    public var electionDayHours: Hours? {
        let cal = calendar
        guard let day = cal.date(from: electionDay),
              let open = cal.date(bySettingHour: electionDayOpen.hour, minute: electionDayOpen.minute, second: 0, of: day),
              let close = cal.date(bySettingHour: electionDayClose.hour, minute: electionDayClose.minute, second: 0, of: day)
        else { return nil }
        return Hours(open: open, close: close)
    }

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

    /// Closing time on the final day of the period.
    public var periodEnd: Date? {
        calendar.date(from: lastDay).flatMap { hours(on: $0)?.close }
    }

    /// True once the whole early-voting period is over.
    public func hasEnded(at date: Date) -> Bool {
        periodEnd.map { date >= $0 } ?? false
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
