import Foundation

/// One timeline entry's worth of weather (§10.2).
///
/// Lives in `WeatherCore` so the watch and iOS widget extensions share both the
/// model and the views built on it.
public struct WeatherEntrySnapshot: Sendable, Equatable {
    public let date: Date
    public let locationName: String
    public let temperature: Double?      // °C
    public let high: Double?
    public let low: Double?
    public let rainChance: Int?
    public let conditionCode: Int?
    public let isDay: Bool
    /// Signed difference from the rolling normal, in °C. `nil` until the phone
    /// has synced normals for this place.
    public let temperatureDelta: Double?
    public let imperial: Bool
    /// The next sunrise or sunset, whichever comes first.
    public let nextSunEvent: SunEvent?
    /// The location's timezone, needed to render `nextSunEvent` as a wall clock.
    public let timeZoneIdentifier: String?

    public init(
        date: Date,
        locationName: String,
        temperature: Double?,
        high: Double?,
        low: Double?,
        rainChance: Int?,
        conditionCode: Int?,
        isDay: Bool,
        temperatureDelta: Double?,
        imperial: Bool,
        nextSunEvent: SunEvent? = nil,
        timeZoneIdentifier: String? = nil
    ) {
        self.date = date
        self.locationName = locationName
        self.temperature = temperature
        self.high = high
        self.low = low
        self.rainChance = rainChance
        self.conditionCode = conditionCode
        self.isDay = isDay
        self.temperatureDelta = temperatureDelta
        self.imperial = imperial
        self.nextSunEvent = nextSunEvent
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public var formatter: UnitFormatter { UnitFormatter(imperial: imperial) }

    public var locationTimeZone: TimeZone {
        timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// `"↓20:45"` — the marker plus the clock time, sized for a curved label.
    public var sunEventText: String? {
        guard let nextSunEvent else { return nil }
        return nextSunEvent.kind.marker
            + nextSunEvent.formattedTime(timeZone: locationTimeZone)
    }

    /// Spelled out for VoiceOver, where "↓" reads as nothing useful.
    public var sunEventAccessibilityText: String? {
        guard let nextSunEvent else { return nil }
        return "\(nextSunEvent.kind.spokenName) at "
            + nextSunEvent.formattedTime(timeZone: locationTimeZone)
    }
    public var condition: WMOCode.Descriptor { WMOCode.describe(conditionCode) }
    public var symbolName: String { condition.symbol(isDay: isDay) }

    /// Where `temperature` sits between today's low and high, 0…1 — the corner
    /// complication's gauge.
    public var positionInRange: Double? {
        guard let temperature, let high, let low, high > low else { return nil }
        return min(max((temperature - low) / (high - low), 0), 1)
    }

    /// "+3°" / "−2°" / "≈", in display units (a delta scales only — §14.5).
    public var deltaText: String? {
        guard let temperatureDelta else { return nil }
        let converted = formatter.temperatureDelta(temperatureDelta)
        if abs(converted) < 1 { return "≈" }
        let rounded = Int(abs(converted).rounded())
        return "\(converted > 0 ? "+" : "−")\(rounded)°"
    }

    /// The full badge sentence used on the rectangular families.
    public var deltaSentence: String? {
        guard let temperatureDelta else { return nil }
        if abs(temperatureDelta) < 1 { return "Near normal" }
        let magnitude = Int(abs(formatter.temperatureDelta(temperatureDelta)).rounded())
        return "\(magnitude)\(formatter.temperatureUnit) "
            + (temperatureDelta > 0 ? "warmer" : "colder") + " than normal"
    }

    /// Placeholder used for widget previews and the gallery.
    public static let placeholder = WeatherEntrySnapshot(
        date: Date(),
        locationName: "London",
        temperature: 21,
        high: 24,
        low: 15,
        rainChance: 40,
        conditionCode: 2,
        isDay: true,
        temperatureDelta: 3,
        imperial: false,
        nextSunEvent: SunEvent(kind: .sunset, timeString: "2026-08-05T20:45"),
        timeZoneIdentifier: "Europe/London")

    /// Shown when there is no cached location at all (§10.2).
    public static func empty(date: Date = Date()) -> WeatherEntrySnapshot {
        WeatherEntrySnapshot(
            date: date, locationName: "Open app", temperature: nil, high: nil, low: nil,
            rainChance: nil, conditionCode: nil, isDay: true, temperatureDelta: nil,
            imperial: false)
    }

    public var isEmpty: Bool { temperature == nil && conditionCode == nil }
}
