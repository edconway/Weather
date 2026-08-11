import Foundation

/// Display formatting for the two unit systems (§5.3).
///
/// Everything is stored internally in metric — °C, km/h, mm — exactly as the API
/// returns it, and converted only here. Port of the `fT` / `fW` / `fP` / `nT` /
/// `uvLabel` helpers in `app.js`.
public struct UnitFormatter: Sendable, Equatable {
    public static let placeholder = "—"

    public let imperial: Bool

    public init(imperial: Bool) {
        self.imperial = imperial
    }

    /// The plan's §1.4.5 default: imperial in the US, metric elsewhere.
    public static var localeDefault: UnitFormatter {
        UnitFormatter(imperial: Locale.current.measurementSystem == .us)
    }

    // MARK: - Raw conversions

    public static func celsiusToFahrenheit(_ celsius: Double) -> Double { celsius * 9 / 5 + 32 }
    public static func kmhToMph(_ kmh: Double) -> Double { kmh * 0.621371 }
    public static func mmToInches(_ mm: Double) -> Double { mm * 0.0393701 }

    /// Temperature in display units, unformatted — for chart axes.
    public func temperatureValue(_ celsius: Double) -> Double {
        imperial ? Self.celsiusToFahrenheit(celsius) : celsius
    }

    public func windValue(_ kmh: Double) -> Double {
        imperial ? Self.kmhToMph(kmh) : kmh
    }

    public func precipitationValue(_ mm: Double) -> Double {
        imperial ? Self.mmToInches(mm) : mm
    }

    /// A temperature **difference**, which scales by 9/5 with no offset (§14.5).
    public func temperatureDelta(_ celsiusDelta: Double) -> Double {
        imperial ? celsiusDelta * 9 / 5 : celsiusDelta
    }

    // MARK: - Symbols

    public var temperatureUnit: String { imperial ? "°F" : "°C" }
    public var windUnit: String { imperial ? "mph" : "km/h" }
    public var precipitationUnit: String { imperial ? "in" : "mm" }
    /// The bare degree marker used where the unit is already established.
    public var degreeSymbol: String { "°" }

    // MARK: - Fixed-point rendering

    /// Equivalent of JavaScript's `Number.toFixed`.
    ///
    /// `String(format: "%.1f", …)` rounds exact binary halves to even (1.25 →
    /// "1.2"), while `toFixed` rounds them away from zero (1.25 → "1.3"). The
    /// difference only bites on values exactly representable at the half, but it
    /// would show up as a 0.1 mm disagreement with the web app.
    ///
    /// `toFixed` rounds the double's *true* decimal expansion, so scaling by a
    /// power of ten first is not equivalent — `4.05 * 10` rounds up to exactly
    /// 40.5 and would yield "4.1" where `toFixed` yields "4.0". Expanding to a
    /// decimal and rounding there reproduces it faithfully.
    static func fixed(_ value: Double, _ places: Int) -> String {
        guard value.isFinite,
              var expanded = Decimal(string: String(format: "%.20f", value))
        else { return String(format: "%.\(places)f", value) }

        var rounded = Decimal()
        // `.plain` is round-half-away-from-zero, matching toFixed.
        NSDecimalRound(&rounded, &expanded, places, .plain)
        return String(format: "%.\(places)f", NSDecimalNumber(decimal: rounded).doubleValue)
    }

    // MARK: - Formatted values

    /// `21°C` / `70°F`.
    public func temperature(_ celsius: Double?) -> String {
        guard let celsius else { return Self.placeholder }
        return "\(Int(temperatureValue(celsius).rounded()))\(temperatureUnit)"
    }

    /// `21°` — used where the unit appears once in a nearby label.
    public func temperatureShort(_ celsius: Double?) -> String {
        guard let celsius else { return Self.placeholder }
        return "\(Int(temperatureValue(celsius).rounded()))°"
    }

    public func temperatureNumber(_ celsius: Double?) -> Int? {
        celsius.map { Int(temperatureValue($0).rounded()) }
    }

    /// `14 km/h` / `9 mph`.
    public func wind(_ kmh: Double?) -> String {
        guard let kmh else { return Self.placeholder }
        return "\(Int(windValue(kmh).rounded())) \(windUnit)"
    }

    /// `1.2 mm` / `0.05"`.
    public func precipitation(_ mm: Double?) -> String {
        guard let mm else { return Self.placeholder }
        return imperial
            ? "\(Self.fixed(Self.mmToInches(mm), 2))\""
            : "\(Self.fixed(mm, 1)) mm"
    }

    /// Compact variant used inside charts, where "—" reads better than "0.0 mm".
    public func precipitationCompact(_ mm: Double?) -> String {
        guard let mm else { return Self.placeholder }
        if imperial {
            let inches = Self.mmToInches(mm)
            return inches < 0.01 ? Self.placeholder : "\(Self.fixed(inches, 2))\""
        }
        return mm < 0.1 ? Self.placeholder : "\(Self.fixed(mm, 1))mm"
    }

    /// `3.4 Moderate`.
    public func uvIndex(_ value: Double?) -> String {
        guard let value else { return Self.placeholder }
        return "\(Self.fixed(value, 1)) \(Self.uvLabel(value))"
    }

    /// Just the number — the watch has no room for the band name.
    public func uvIndexCompact(_ value: Double?) -> String {
        guard let value else { return Self.placeholder }
        return Self.fixed(value, 1)
    }

    public static func uvLabel(_ value: Double) -> String {
        switch value {
        case ...2: return "Low"
        case ...5: return "Moderate"
        case ...7: return "High"
        case ...10: return "Very High"
        default: return "Extreme"
        }
    }

    public func rainChance(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? Self.placeholder
    }

    // MARK: - Chart axis labels

    /// Precipitation axis tick. Takes a value that is **already in display
    /// units**, which is what a chart axis hands back.
    ///
    /// Must not truncate: `Int(1.5)` is 1, which made consecutive ticks render
    /// as "1" and "1". Keeps a decimal whenever the value has one.
    public func precipitationAxis(displayValue: Double) -> String {
        if displayValue == 0 { return "0" }
        if imperial {
            return displayValue < 0.1 ? Self.fixed(displayValue, 2) : Self.fixed(displayValue, 1)
        }
        if displayValue < 10 {
            return displayValue.rounded() == displayValue
                ? "\(Int(displayValue))"
                : Self.fixed(displayValue, 1)
        }
        return "\(Int(displayValue.rounded()))"
    }

    /// Temperature axis tick — always a whole degree with a degree sign.
    public func temperatureAxis(_ displayValue: Double) -> String {
        "\(Int(displayValue.rounded()))°"
    }
}
