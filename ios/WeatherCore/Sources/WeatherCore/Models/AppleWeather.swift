import Foundation

/// On-device Apple Weather minute rain, after WeatherKit types have been stripped off.
///
/// Open-Meteo remains the forecast, the history, and every normal. These values
/// are only what `WeatherService` returned for minute precipitation and alerts.
/// Nothing here is filled in from an hourly estimate.
public struct AppleMinutePoint: Codable, Sendable, Equatable, Identifiable {
    public let date: Date
    /// Millimetres per hour. Display conversion happens in `UnitFormatter`.
    public let intensityMillimetresPerHour: Double
    /// 0...1.
    public let chance: Double

    public var id: Date { date }

    public init(date: Date, intensityMillimetresPerHour: Double, chance: Double) {
        self.date = date
        self.intensityMillimetresPerHour = intensityMillimetresPerHour
        self.chance = chance
    }
}

public struct AppleWeatherAlert: Codable, Sendable, Equatable, Identifiable {
    public let summary: String
    public let detailsURL: URL

    public var id: String { summary + "\n" + detailsURL.absoluteString }

    public init(summary: String, detailsURL: URL) {
        self.summary = summary
        self.detailsURL = detailsURL
    }
}

/// Legal attribution from `WeatherService.attribution`. Shown wherever Apple data is drawn.
public struct AppleWeatherAttribution: Codable, Sendable, Equatable {
    public let serviceName: String
    public let legalPageURL: URL?
    public let legalAttributionText: String?
    public let markLightURL: URL?
    public let markDarkURL: URL?

    public init(
        serviceName: String,
        legalPageURL: URL?,
        legalAttributionText: String?,
        markLightURL: URL?,
        markDarkURL: URL?
    ) {
        self.serviceName = serviceName
        self.legalPageURL = legalPageURL
        self.legalAttributionText = legalAttributionText
        self.markLightURL = markLightURL
        self.markDarkURL = markDarkURL
    }
}

public enum AppleMinuteAvailability: String, Codable, Sendable, Equatable {
    case available
    case unavailable
}

public enum AppleWeatherFailure: String, Codable, Sendable, Equatable {
    /// JWT / entitlement / WeatherKit app service. The UI must not show the raw error.
    case notAuthorised
    case offline
    case unavailable
}

public struct AppleWeatherSnapshot: Codable, Sendable, Equatable {
    public var minutes: [AppleMinutePoint]
    public var alerts: [AppleWeatherAlert]
    public var minuteAvailability: AppleMinuteAvailability
    /// Nil when Apple answered. The raw system text stays in the log, not here.
    public var failure: AppleWeatherFailure?
    public var attribution: AppleWeatherAttribution?
    public var fetchedAt: Date
    /// In-memory cache deadline. Not a disk cache.
    public var expiresAt: Date

    public init(
        minutes: [AppleMinutePoint],
        alerts: [AppleWeatherAlert],
        minuteAvailability: AppleMinuteAvailability,
        failure: AppleWeatherFailure?,
        attribution: AppleWeatherAttribution?,
        fetchedAt: Date,
        expiresAt: Date
    ) {
        self.minutes = minutes
        self.alerts = alerts
        self.minuteAvailability = minuteAvailability
        self.failure = failure
        self.attribution = attribution
        self.fetchedAt = fetchedAt
        self.expiresAt = expiresAt
    }

    /// Minutes the iPhone UI may draw. Empty unless Apple actually returned some.
    public var displayMinutes: [AppleMinutePoint] {
        guard failure == nil, minuteAvailability == .available, !minutes.isEmpty else { return [] }
        return minutes
    }
}

public struct SourceStatusLine: Equatable, Sendable {
    public let text: String
    public let badge: String

    public init(text: String, badge: String) {
        self.text = text
        self.badge = badge
    }
}

public enum AppleWeatherStatus {
    public static let notAuthorisedHoldOff: TimeInterval = 15 * 60

    /// `1 m/s` is `3_600_000 mm/h`. WeatherKit reports intensity as `UnitSpeed`.
    public static func millimetresPerHour(fromMetresPerSecond metresPerSecond: Double) -> Double {
        metresPerSecond * 3_600_000
    }

    public static func classify(_ error: Error) -> AppleWeatherFailure {
        let reflected = String(reflecting: error)
        let description = error.localizedDescription
        let domain = (error as NSError).domain
        if domain.contains("WDSJWTAuthenticator")
            || reflected.contains("WDSJWTAuthenticator")
            || description.localizedCaseInsensitiveContains("entitlement")
            || description.localizedCaseInsensitiveContains("not authorized")
            || description.localizedCaseInsensitiveContains("not authorised") {
            return .notAuthorised
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost:
                return .offline
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: ns.code) {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost:
                return .offline
            default:
                break
            }
        }
        return .unavailable
    }

    public static func shouldHoldOff(lastNotAuthorisedAt: Date?, now: Date, bypass: Bool) -> Bool {
        guard !bypass, let lastNotAuthorisedAt else { return false }
        return now.timeIntervalSince(lastNotAuthorisedAt) < notAuthorisedHoldOff
    }

    /// Cache a successful answer until `expiresAt`. Failures are not cached;
    /// `notAuthorised` uses the in-memory hold-off instead.
    public static func shouldCache(_ snapshot: AppleWeatherSnapshot, now: Date) -> Bool {
        snapshot.failure == nil && snapshot.expiresAt > now
    }

    public static func appleLine(_ snapshot: AppleWeatherSnapshot?) -> SourceStatusLine {
        guard let snapshot else {
            return SourceStatusLine(
                text: "Minute-by-minute rain — Apple Weather · checking",
                badge: "Checking")
        }
        switch snapshot.failure {
        case .notAuthorised:
            return SourceStatusLine(
                text: "Minute-by-minute rain — Apple Weather · Apple hasn't enabled this for the app yet; using Open-Meteo estimates",
                badge: "Off")
        case .offline, .unavailable:
            return SourceStatusLine(
                text: "Minute-by-minute rain — Apple Weather · couldn't reach Apple Weather; using Open-Meteo estimates",
                badge: "Retry")
        case nil:
            if !snapshot.displayMinutes.isEmpty {
                return SourceStatusLine(
                    text: "Minute-by-minute rain — Apple Weather · available here",
                    badge: "Live")
            }
            return SourceStatusLine(
                text: "Minute-by-minute rain — Apple Weather · not offered for this location; using Open-Meteo estimates",
                badge: "Limited")
        }
    }

    public static func openMeteoLine(
        isStale: Bool, updatedAt: Date?, now: Date, timeZone: TimeZone
    ) -> SourceStatusLine {
        guard let updatedAt else {
            return isStale
                ? SourceStatusLine(
                    text: "Forecast & climate history — Open-Meteo · last updated earlier",
                    badge: "Offline")
                : SourceStatusLine(
                    text: "Forecast & climate history — Open-Meteo · waiting for the forecast",
                    badge: "Checking")
        }
        let clock = clockTime(updatedAt, timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if !isStale && calendar.isDate(updatedAt, inSameDayAs: now) {
            return SourceStatusLine(
                text: "Forecast & climate history — Open-Meteo · updated \(clock)",
                badge: "Live")
        }
        let day = relativeDay(updatedAt, now: now, calendar: calendar)
        return SourceStatusLine(
            text: "Forecast & climate history — Open-Meteo · last updated \(day) \(clock)",
            badge: isStale ? "Offline" : "Live")
    }

    public static func summary(
        minutes: [AppleMinutePoint], timeZone: TimeZone, formatter: UnitFormatter
    ) -> (headline: String, detail: String) {
        guard let firstWet = minutes.first(where: {
            $0.intensityMillimetresPerHour > 0
        }) else {
            return ("No rain in the next hour", "Dry for the whole hour")
        }
        let peak = minutes.map(\.intensityMillimetresPerHour).max() ?? firstWet.intensityMillimetresPerHour
        let rate = formatter.precipitation(peak) + "/h"
        let start = minutes.first?.date ?? firstWet.date
        if firstWet.date.timeIntervalSince(start) < 60 {
            return ("Rain now", "Peak \(rate)")
        }
        return ("Rain at \(clockTime(firstWet.date, timeZone: timeZone))", "Peak \(rate)")
    }

    static func clockTime(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private static func relativeDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDateInYesterday(date) { return "yesterday" }
        if calendar.isDateInToday(date) { return "today" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
        if let days, days > 1 { return "\(days) days ago" }
        return "earlier"
    }
}
