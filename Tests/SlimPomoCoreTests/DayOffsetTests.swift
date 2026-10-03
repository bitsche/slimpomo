import Foundation
import Testing
@testable import SlimPomoCore

struct DayOffsetTests {
    private func calendar(_ zone: String = "Europe/Berlin") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ c: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func sameDayHasNoSuffix() {
        let c = calendar()
        let now = date(c, 2026, 10, 2, 23, 50)
        #expect(DayOffset.days(of: date(c, 2026, 10, 2, 23, 59), from: now, calendar: c) == 0)
        #expect(DayOffset.suffix(of: date(c, 2026, 10, 2, 0, 0), from: now, calendar: c) == nil)
    }

    @Test func pastMidnightIsPlusOne() {
        let c = calendar()
        let now = date(c, 2026, 10, 2, 23, 50)
        #expect(DayOffset.suffix(of: date(c, 2026, 10, 3, 0, 5), from: now, calendar: c) == "(+1)")
        #expect(DayOffset.suffix(of: date(c, 2026, 10, 3, 4, 44), from: now, calendar: c) == "(+1)")
    }

    @Test func laterDaysCount() {
        let c = calendar()
        let now = date(c, 2026, 10, 2, 9)
        #expect(DayOffset.suffix(of: date(c, 2026, 10, 4, 1), from: now, calendar: c) == "(+2)")
        #expect(DayOffset.days(of: date(c, 2026, 11, 2, 1), from: now, calendar: c) == 31)
    }

    @Test func offsetDisappearsAfterMidnight() {
        let c = calendar()
        let finish = date(c, 2026, 10, 3, 4, 44)
        #expect(DayOffset.suffix(of: finish, from: date(c, 2026, 10, 2, 23, 59), calendar: c) == "(+1)")
        #expect(DayOffset.suffix(of: finish, from: date(c, 2026, 10, 3, 0, 1), calendar: c) == nil)
    }

    @Test func dayLightSavingChangeStaysOnCalendarDays() {
        let c = calendar()
        let now = date(c, 2026, 10, 24, 22)
        #expect(DayOffset.days(of: date(c, 2026, 10, 26, 1), from: now, calendar: c) == 2)
        #expect(DayOffset.days(of: date(c, 2026, 10, 25, 23), from: now, calendar: c) == 1)
    }

    @Test func earlierTimesNeverGoNegative() {
        let c = calendar()
        #expect(DayOffset.days(of: date(c, 2026, 10, 1, 12), from: date(c, 2026, 10, 2, 9), calendar: c) == 0)
    }
}
