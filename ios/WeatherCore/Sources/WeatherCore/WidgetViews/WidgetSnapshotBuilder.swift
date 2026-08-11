import Foundation

/// Turns cached forecast + normals into the six hourly timeline entries a
/// provider needs (§10.2).
///
/// Kept out of the extensions so it can be unit-tested against the fixtures —
/// §11.2's "given cached fixture data, produces 6 hourly entries with correct
/// temps".
public enum WidgetSnapshotBuilder {
    public static let entryCount = 6

    public static func entries(
        forecast: ForecastResponse,
        location: WeatherLocation,
        payload: WatchSyncPayload?,
        imperial: Bool,
        now: Date
    ) -> [WeatherEntrySnapshot] {
        let conditions = CurrentConditions(forecast: forecast, now: now)
        let dateKit = DateKit(timeZone: forecast.locationTimeZone)
        let hourly = forecast.hourly
        let daily = forecast.daily

        // Hi/lo and rain chance are properties of the day, so they stay fixed
        // across the six entries.
        let high = daily.temperature2mMax.value(at: conditions.todayIndex)
        let low = daily.temperature2mMin.value(at: conditions.todayIndex)
        let rainChance = daily.precipitationProbabilityMax.value(at: conditions.todayIndex)

        // Normals only apply when they describe this place (§9.2).
        let applicablePayload = payload.flatMap {
            WatchSyncEnvelope.isApplicable($0, to: location) ? $0 : nil
        }
        let todayNormal = applicablePayload?.tempBand?.today
        let timeZoneIdentifier = forecast.locationTimeZone.identifier

        return (0..<entryCount).compactMap { offset -> WeatherEntrySnapshot? in
            let index = conditions.nowIndex + offset
            guard index < hourly.time.count else { return nil }
            let timeString = hourly.time[index]
            guard let entryDate = dateKit.date(fromHourString: timeString) else { return nil }

            // The first entry is "now"; later ones start at their own hour.
            let effectiveDate = offset == 0 ? now : entryDate
            // Recomputed per entry, so the corner flips from "sunset" to
            // "sunrise" at dusk without waiting for a timeline reload.
            let sunEvent = SunEvent.next(forecast: forecast, now: effectiveDate)

            var delta: Double?
            if let normalHigh = todayNormal?.tMax, let normalLow = todayNormal?.tMin,
               let high, let low {
                delta = (high + low) / 2 - (normalHigh + normalLow) / 2
            }

            return WeatherEntrySnapshot(
                date: effectiveDate,
                locationName: location.shortName,
                temperature: hourly.temperature2m.value(at: index),
                high: high,
                low: low,
                rainChance: rainChance,
                conditionCode: hourly.weatherCode.value(at: index)
                    ?? daily.weatherCode.value(at: conditions.todayIndex),
                isDay: (hourly.isDay.value(at: index) ?? 1) != 0,
                temperatureDelta: delta,
                imperial: imperial,
                nextSunEvent: sunEvent,
                timeZoneIdentifier: timeZoneIdentifier)
        }
    }
}
