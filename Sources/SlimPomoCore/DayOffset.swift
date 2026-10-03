import Foundation

/// How many local calendar days a computed time lies after today. Planned finish times that cross midnight carry it.
public enum DayOffset {
    /// Zero for a time on today's date, or earlier. Calendar days, not 24 hour spans.
    public static func days(of date: Date, from now: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: start, to: target).day ?? 0)
    }

    /// "(+1)" for tomorrow, "(+2)" for the day after, and nil for today.
    public static func suffix(of date: Date, from now: Date, calendar: Calendar = .current) -> String? {
        let days = days(of: date, from: now, calendar: calendar)
        return days > 0 ? "(+\(days))" : nil
    }
}
