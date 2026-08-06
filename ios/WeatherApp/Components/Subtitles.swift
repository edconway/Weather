import Foundation
import WeatherCore

/// Chart subtitles, word-for-word from the templates in `renderContent`
/// (`app.js`), including the location short-name and the historical year ranges.
///
/// Main-actor isolated because every input is read straight off the store.
@MainActor
enum Subtitles {

    /// `" for London"`, or empty when the name is unknown.
    private static func locationSuffix(_ store: WeatherStore) -> String {
        guard let short = store.location?.shortName, !short.isEmpty else { return "" }
        return " for \(short)"
    }

    static func hourlyTemp(_ store: WeatherStore) -> String {
        let range = store.hourlyNormals.map { "\($0.temp.yearStart)–\($0.temp.yearEnd) avg" }
            ?? "historical avg"
        return "Hourly temperature\(locationSuffix(store)) · actual & forecast vs \(range)"
    }

    static func dailyTemp(_ store: WeatherStore) -> String {
        guard let band = store.tempBand else {
            return "14-day high/low\(locationSuffix(store))"
        }
        return "14-day high/low\(locationSuffix(store)) · vs 7-day rolling avg "
            + "\(band.histYearStart)–\(band.histYearEnd)"
    }

    static func hourlyWetBulb(_ store: WeatherStore) -> String {
        let range = store.hourlyNormals.map { "\($0.wetBulb.yearStart)–\($0.wetBulb.yearEnd) avg" }
            ?? "historical avg"
        return "Hourly wet bulb\(locationSuffix(store)) · actual & forecast vs \(range)"
    }

    static func dailyWetBulb(_ store: WeatherStore) -> String {
        guard let band = store.tempBand else {
            return "14-day wet bulb high/low\(locationSuffix(store))"
        }
        return "14-day wet bulb high/low\(locationSuffix(store)) · vs 7-day rolling avg "
            + "\(band.histYearStart)–\(band.histYearEnd)"
    }

    static func hourlyRain(_ store: WeatherStore) -> String {
        let suffix = store.hourlyNormals.map { " · vs \($0.rain.yearStart)–\($0.rain.yearEnd) avg" }
            ?? ""
        return "Hourly precipitation\(locationSuffix(store))\(suffix)"
    }

    static func dailyRain(_ store: WeatherStore) -> String {
        "14-day precipitation\(locationSuffix(store)) · past 7 days actual, next 7 days forecast"
    }

    static func ytdRain(_ store: WeatherStore) -> String {
        guard let ytd = store.ytdRain else {
            return "Cumulative rainfall\(locationSuffix(store))"
        }
        // "2026-08-05" → "08/05", matching `latestDate.slice(5).replace('-','/')`.
        let through = ytd.latestDate.count >= 10
            ? " · through " + ytd.latestDate.dropFirst(5).replacingOccurrences(of: "-", with: "/")
            : ""
        return "Cumulative rainfall\(locationSuffix(store)) · \(ytd.thisYear) actual & "
            + "7-day forecast vs \(ytd.startYear)–\(ytd.thisYear - 1) avg\(through)"
    }

    static func climate(_ store: WeatherStore) -> String {
        guard let climatology = store.climatology else {
            return "Climate normals\(locationSuffix(store))"
        }
        // `°${uT().slice(1)}` — the unit letter without the degree sign.
        let unitLetter = store.imperial ? "F" : "C"
        return "Avg monthly high/low °\(unitLetter) (lines) & total rainfall (bars)"
            + "\(locationSuffix(store)) · \(climatology.yearStart)–\(climatology.yearEnd)"
    }
}
