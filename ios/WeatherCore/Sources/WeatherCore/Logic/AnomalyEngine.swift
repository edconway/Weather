import Foundation

/// The three hero badges (§6.8) — ports of `_tempAnomaly`, `_rainAnomaly` and
/// `_wbAnomaly`.
///
/// All comparisons run in °C and mm; only the displayed number is converted.
/// Each badge returns `nil` until its archive-derived input has arrived, which
/// is what makes them appear progressively.
public enum AnomalyEngine {

    // MARK: - Temperature

    /// `delta = (hi + lo) / 2 − (histMax + histMin) / 2`, in °C.
    ///
    /// `|delta| < 1 °C` reads "Near normal"; otherwise the delta is shown in the
    /// user's units — scaled by 9/5 with **no** +32, because it is a difference
    /// (§14.5).
    public static func temperature(
        conditions: CurrentConditions,
        todayNormal: DayNormal?,
        formatter: UnitFormatter
    ) -> Anomaly? {
        guard let normal = todayNormal,
              let histMax = normal.tMax, let histMin = normal.tMin,
              let high = conditions.high, let low = conditions.low
        else { return nil }

        let forecastMean = (high + low) / 2
        let historicalMean = (histMax + histMin) / 2
        let delta = forecastMean - historicalMean
        let magnitude = abs(delta)

        if magnitude < 1 {
            return Anomaly(
                text: "Near normal", kind: .neutral, panel: .temperature,
                detail: "Today's average temperature is within 1°C of the usual "
                    + "reading for this date.")
        }

        let displayed = Int(formatter.temperatureDelta(magnitude).rounded())
        let direction = delta > 0 ? "warmer" : "colder"
        return Anomaly(
            text: "\(displayed)\(formatter.temperatureUnit) \(direction) than normal",
            kind: delta > 0 ? .warm : .cold,
            panel: .temperature,
            detail: "Compared with the rolling ±3-day average for this date.")
    }

    // MARK: - Rain

    /// Same five branches as `classifyRain`, but with the badge's own wording.
    public static func rain(today: DailyRainNormal?) -> Anomaly? {
        guard let today else { return nil }

        if today.forecastMm < 0.1 {
            return Anomaly(
                text: today.histMeanMm >= 1 ? "Drier than normal" : "Dry day expected",
                kind: .dry, panel: .rain,
                detail: "No measurable rain in today's forecast.")
        }
        if today.p90Mm > 0 && today.forecastMm >= today.p90Mm {
            return Anomaly(
                text: "Unusually wet", kind: .wet, panel: .rain,
                detail: "Heavier than 9 in 10 comparable days on record.")
        }
        if today.forecastMm > today.histMeanMm * 1.5,
           today.forecastMm - today.histMeanMm >= 1 {
            return Anomaly(
                text: "Wetter than normal", kind: .wet, panel: .rain,
                detail: "More than half again the usual rainfall for this date.")
        }
        if today.histMeanMm > 0.5, today.forecastMm < today.histMeanMm * 0.5 {
            return Anomaly(
                text: "Drier than normal", kind: .dry, panel: .rain,
                detail: "Under half the usual rainfall for this date.")
        }
        return Anomaly(
            text: "Near normal rainfall", kind: .neutral, panel: .rain,
            detail: "Close to the usual rainfall for this date.")
    }

    // MARK: - Mugginess

    static let muggyDetail =
        "Based on wet bulb temperature vs the usual reading for this time of day"

    /// Suppressed entirely when the normal wet bulb is below 8 °C — the ratio is
    /// meaningless in cool weather and produces wild percentages.
    public static func mugginess(
        conditions: CurrentConditions,
        hourlyWetBulb: HourAverages?,
        todayNormal: DayNormal?
    ) -> Anomaly? {
        guard let wetBulbNow = conditions.wetBulbNow else { return nil }

        var normal = hourlyWetBulb?.avgByHour.value(at: conditions.currentHour)
        if normal == nil, let day = todayNormal,
           let wbMax = day.wbMax, let wbMin = day.wbMin {
            normal = (wbMax + wbMin) / 2
        }
        guard let normal, normal >= 8 else { return nil }

        let percent = Int((((wetBulbNow - normal) / normal) * 100).rounded())
        if abs(percent) < 5 {
            return Anomaly(
                text: "Near normal mugginess", kind: .neutral, panel: .wetBulb,
                detail: muggyDetail)
        }
        let magnitude = abs(percent)
        return Anomaly(
            text: "Feels \(magnitude)% \(percent > 0 ? "more" : "less") muggy than usual",
            kind: percent > 0 ? .muggy : .muggyLow,
            panel: .wetBulb,
            detail: muggyDetail)
    }

    // MARK: - Composition

    /// Hero order, matching the web app: mugginess, temperature, rain.
    public static func heroBadges(
        conditions: CurrentConditions,
        tempBand: TempBand?,
        dailyRain: [DailyRainNormal],
        hourlyNormals: HourlyNormals?,
        formatter: UnitFormatter
    ) -> [Anomaly] {
        let todayNormal = tempBand?.today
        return [
            mugginess(
                conditions: conditions,
                hourlyWetBulb: hourlyNormals?.wetBulb,
                todayNormal: todayNormal),
            temperature(
                conditions: conditions, todayNormal: todayNormal, formatter: formatter),
            rain(today: dailyRain.first)
        ].compactMap { $0 }
    }

    /// The single badge the watch shows (§9): temperature when it is at least
    /// 1 °C off normal, else mugginess, else a non-neutral rain badge.
    public static func watchBadge(
        conditions: CurrentConditions,
        tempBand: TempBand?,
        dailyRain: [DailyRainNormal],
        hourlyNormals: HourlyNormals?,
        formatter: UnitFormatter
    ) -> Anomaly? {
        let todayNormal = tempBand?.today
        if let temp = temperature(
            conditions: conditions, todayNormal: todayNormal, formatter: formatter),
           temp.kind != .neutral {
            return temp
        }
        if let muggy = mugginess(
            conditions: conditions,
            hourlyWetBulb: hourlyNormals?.wetBulb,
            todayNormal: todayNormal) {
            return muggy
        }
        if let rainBadge = rain(today: dailyRain.first), rainBadge.kind != .neutral {
            return rainBadge
        }
        return nil
    }
}
