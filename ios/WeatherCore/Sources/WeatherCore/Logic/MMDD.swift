import Foundation

/// Calendar-day distance between two `"MM-DD"` strings, year-wrap aware.
///
/// Port of `_mmddDist` in `app.js`: computed in a fixed leap year (2020), then
/// wrapped so that Dec 30 and Jan 2 are 3 days apart rather than 362.
public enum MMDD {
    private static let cumulativeDays2020 = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]

    /// Day-of-year (0-based) for `"MM-DD"` in a leap year, or `nil` if malformed.
    static func dayOfYear(_ mmdd: String) -> Int? {
        let parts = mmdd.split(separator: "-")
        guard parts.count == 2,
              let month = Int(parts[0]), let day = Int(parts[1]),
              (1...12).contains(month), day >= 1 else { return nil }
        return cumulativeDays2020[month - 1] + (day - 1)
    }

    /// Wrapped absolute distance in days. Returns `Int.max` for malformed input
    /// so callers' `<= 3` window checks simply exclude it.
    public static func distance(_ a: String, _ b: String) -> Int {
        guard let da = dayOfYear(a), let db = dayOfYear(b) else { return .max }
        var d = da - db
        if d > 182 { d -= 365 }
        if d < -182 { d += 365 }
        return abs(d)
    }
}
