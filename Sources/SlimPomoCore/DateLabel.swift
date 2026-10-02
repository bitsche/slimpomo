import Foundation

/// The UI is English, so dates read the same on every system region: `Mon 5 Oct`, never `Mo., 5. Okt.`.
/// The pattern is fixed rather than a localized template, because a template reorders itself (`Mon, Oct 5`).
public enum DateLabel {
    public static func weekday(_ date: Date, calendar: Calendar) -> String {
        formatted(date, pattern: "EEE", calendar: calendar)
    }

    /// `Mon 5 Oct`, with the year (`Mon 5 Oct 2025`) when asked.
    public static func dayMonth(_ date: Date, calendar: Calendar, includeYear: Bool = false) -> String {
        formatted(date, pattern: includeYear ? "EEE d MMM yyyy" : "EEE d MMM", calendar: calendar)
    }

    private static func formatted(_ date: Date, pattern: String, calendar: Calendar) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        gregorian.locale = locale
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// Day headings of History: Today, Yesterday, then `Tue 22 Sep`, with the year when it is not the current one.
public enum HistoryDayTitle {
    public static func text(for day: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            return "Today"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        return DateLabel.dayMonth(day, calendar: calendar, includeYear: !sameYear)
    }
}
