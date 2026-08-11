import Foundation

/// Calendar arithmetic in a **specific** timezone.
///
/// Every "what day/hour is it there" question in the app goes through here so
/// that a searched location on the other side of the world reports its own wall
/// clock, not the device's (PLAN DEVIATION §1.4.2, pitfall §14.2).
public struct DateKit: Sendable {
    public let timeZone: TimeZone
    private let calendar: Calendar

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Fixed locale: these strings are API keys, never user-facing text.
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
    }

    private func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour], from: date)
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }

    /// `"YYYY-MM-DD"` in this timezone.
    public func dateString(_ date: Date) -> String {
        let c = components(date)
        return "\(c.year!)-\(Self.pad(c.month!))-\(Self.pad(c.day!))"
    }

    /// `"MM-DD"` in this timezone.
    public func monthDayString(_ date: Date) -> String {
        let c = components(date)
        return "\(Self.pad(c.month!))-\(Self.pad(c.day!))"
    }

    /// `"YYYY-MM-DDTHH:00"` — the string form used to locate the current hour in
    /// the API's `hourly.time` array.
    public func hourString(_ date: Date) -> String {
        let c = components(date)
        return "\(dateString(date))T\(Self.pad(c.hour!)):00"
    }

    /// `"YYYY-MM-DDTHH:mm"` — minute precision, for comparing against the API's
    /// sunrise/sunset strings.
    public func minuteString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let minute = calendar.component(.minute, from: date)
        let c = components(date)
        return "\(dateString(date))T\(Self.pad(c.hour!)):\(Self.pad(minute))"
    }

    public func year(_ date: Date) -> Int { components(date).year! }
    public func month(_ date: Date) -> Int { components(date).month! }
    public func day(_ date: Date) -> Int { components(date).day! }
    public func hour(_ date: Date) -> Int { components(date).hour! }

    /// `date` shifted by whole days, staying on the same wall-clock hour.
    public func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// `"YYYY-MM-DD"` for `date + days`.
    public func dateString(offsetDays days: Int, from date: Date) -> String {
        dateString(addingDays(days, to: date))
    }

    /// `"MM-DD"` for `date + days`.
    public func monthDayString(offsetDays days: Int, from date: Date) -> String {
        monthDayString(addingDays(days, to: date))
    }

    /// Midday on the given calendar date, useful for label formatting where the
    /// exact instant does not matter but DST edges do.
    public func noon(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12
        return calendar.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// Parses `"YYYY-MM-DD"` (or the `"...THH:mm"` form) into midday of that
    /// date in this timezone. Display formatting only — never for indexing.
    public func date(fromDayString string: String) -> Date? {
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        return noon(year: y, month: m, day: d)
    }

    /// Parses `"YYYY-MM-DDTHH:mm"` into that instant in this timezone.
    /// Display and chart-axis use only — never for indexing.
    public func date(fromHourString string: String) -> Date? {
        guard string.count >= 13 else { return date(fromDayString: string) }
        let datePart = string.prefix(10).split(separator: "-")
        guard datePart.count == 3,
              let y = Int(datePart[0]), let m = Int(datePart[1]), let d = Int(datePart[2]),
              let hour = Int(string.dropFirst(11).prefix(2)) else { return nil }
        let minute = Int(string.dropFirst(14).prefix(2)) ?? 0
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)
    }

    /// Number of whole days from `start` to `end`, both `"YYYY-MM-DD"`.
    public func dayCount(from start: String, to end: String) -> Int? {
        guard let a = date(fromDayString: start), let b = date(fromDayString: end) else { return nil }
        return calendar.dateComponents([.day], from: a, to: b).day
    }
}

extension DateKit {
    /// Formatter for user-facing text, bound to this timezone.
    public func formatted(_ date: Date, _ format: Date.FormatStyle) -> String {
        var style = format
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
