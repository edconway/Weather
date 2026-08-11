import Foundation

/// The next sunrise or sunset, for the corner complication.
///
/// Open-Meteo returns `sunrise`/`sunset` as `"YYYY-MM-DDTHH:mm"` in the
/// location's local time, exactly like every other time string in the response,
/// so the "which comes next" comparison is a string comparison against now in
/// the *location's* timezone (§14.2) — no `Date` parsing for the decision.
public struct SunEvent: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Equatable, Codable {
        case sunrise, sunset

        public var symbolName: String {
            self == .sunrise ? "sunrise.fill" : "sunset.fill"
        }

        /// Compact marker for the curved complication label.
        public var marker: String { self == .sunrise ? "↑" : "↓" }

        public var spokenName: String { self == .sunrise ? "sunrise" : "sunset" }
    }

    public let kind: Kind
    /// `"YYYY-MM-DDTHH:mm"`, location-local.
    public let timeString: String

    public init(kind: Kind, timeString: String) {
        self.kind = kind
        self.timeString = timeString
    }

    /// The first sunrise or sunset strictly after `now`.
    ///
    /// Returns `nil` when the forecast carries no sun times — which is the
    /// honest answer inside the polar circles in midsummer or midwinter, where
    /// Open-Meteo reports nulls because the sun does not cross the horizon.
    public static func next(forecast: ForecastResponse, now: Date) -> SunEvent? {
        let dateKit = DateKit(timeZone: forecast.locationTimeZone)
        let nowString = dateKit.minuteString(now)
        let daily = forecast.daily

        var candidates: [SunEvent] = []
        for index in daily.time.indices {
            if let sunrise = daily.sunrise.value(at: index), sunrise > nowString {
                candidates.append(SunEvent(kind: .sunrise, timeString: sunrise))
            }
            if let sunset = daily.sunset.value(at: index), sunset > nowString {
                candidates.append(SunEvent(kind: .sunset, timeString: sunset))
            }
        }
        return candidates.min { $0.timeString < $1.timeString }
    }

    /// `"20:45"` or `"8:45 PM"`, per the viewer's locale, in the location's zone.
    public func formattedTime(timeZone: TimeZone) -> String {
        guard let date = DateKit(timeZone: timeZone).date(fromHourString: timeString) else {
            // Fall back to the raw clock portion rather than showing nothing.
            return String(timeString.suffix(5))
        }
        var style = Date.FormatStyle().hour().minute()
        style.timeZone = timeZone
        return date.formatted(style)
    }
}
