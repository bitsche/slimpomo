import Foundation
import Testing
@testable import SlimPomoCore

struct DateLabelTests {
    private func calendar(_ locale: String, zone: String = "Europe/Berlin") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test func dayMonthIsEnglishOnAnyRegion() {
        for locale in ["de_DE", "fr_FR", "en_US", "ja_JP", "ar_SA"] {
            let c = calendar(locale)
            #expect(DateLabel.dayMonth(date(c, 2026, 10, 5), calendar: c) == "Mon 5 Oct", "\(locale)")
            #expect(DateLabel.dayMonth(date(c, 2025, 9, 22), calendar: c, includeYear: true) == "Mon 22 Sep 2025", "\(locale)")
        }
    }

    @Test func historyTitlesUseTodayYesterdayThenTheDate() {
        let c = calendar("de_DE")
        let now = date(c, 2026, 10, 2, 9)
        #expect(HistoryDayTitle.text(for: date(c, 2026, 10, 2, 1), now: now, calendar: c) == "Today")
        #expect(HistoryDayTitle.text(for: date(c, 2026, 10, 1, 23), now: now, calendar: c) == "Yesterday")
        #expect(HistoryDayTitle.text(for: date(c, 2026, 9, 22), now: now, calendar: c).uppercased() == "TUE 22 SEP")
        #expect(HistoryDayTitle.text(for: date(c, 2025, 12, 31), now: now, calendar: c) == "Wed 31 Dec 2025")
    }

    @Test func laterHeadingsHaveNoDotAndTheWeekdayIsEnglish() {
        let c = calendar("de_DE")
        #expect(Snooze.heading(for: "2026-10-05", tomorrow: "2026-10-03", calendar: c) == "Mon 5 Oct")
        #expect(Snooze.heading(for: "2026-10-05", tomorrow: "2026-10-05", calendar: c) == "Tomorrow (Mon)")
        let offers = Snooze.offers(on: date(c, 2026, 10, 4), calendar: c)
        #expect(offers.map(\.title) == ["Move to tomorrow (Mon)"])
    }
}
