import Foundation

/// Copy and layout decisions for the scrolling iPhone screen.
///
/// Open-Meteo stays the forecast, the history, and every normal. This type
/// never invents minute-by-minute rain from hourly totals.
public enum ScreenPresentation {

    public struct HeroVoice: Equatable, Sendable {
        public let headline: String
        public let detail: String
        public let panel: PanelID

        public init(headline: String, detail: String, panel: PanelID) {
            self.headline = headline
            self.detail = detail
            self.panel = panel
        }
    }

    public enum RainWhen: String, Equatable, Sendable {
        case rainingNow
        case startingSoon
        case laterToday
        case dry
    }

    /// Hourly Open-Meteo outlook. `prominent` is true only when rain is
    /// happening or due within the next three hours.
    public struct RainOutlook: Equatable, Sendable {
        public let state: RainWhen
        public let headline: String
        public let detail: String?
        public let heroValue: String
        public let hourlyChance: [Int]
        public let prominent: Bool
        /// Always names the estimate. Minute curves come only from WeatherKit.
        public let sourceCaption = "Open-Meteo · hourly estimate"

        public init(
            state: RainWhen, headline: String, detail: String?, heroValue: String,
            hourlyChance: [Int], prominent: Bool
        ) {
            self.state = state
            self.headline = headline
            self.detail = detail
            self.heroValue = heroValue
            self.hourlyChance = hourlyChance
            self.prominent = prominent
        }
    }

    /// Today's high/low against the normal band, as fractions of one track.
    public struct TodayRange: Equatable, Sendable {
        public let low: Double
        public let high: Double
        public let normalLow: Double
        public let normalHigh: Double
        public let now: Double?
        public let normalStart: Double
        public let normalWidth: Double
        public let todayStart: Double
        public let todayWidth: Double
        public let nowFraction: Double?
        public let lowLabelFraction: Double
        public let highLabelFraction: Double
        public let captionFraction: Double

        public init(
            low: Double, high: Double, normalLow: Double, normalHigh: Double, now: Double?,
            normalStart: Double, normalWidth: Double, todayStart: Double, todayWidth: Double,
            nowFraction: Double?, lowLabelFraction: Double, highLabelFraction: Double,
            captionFraction: Double
        ) {
            self.low = low
            self.high = high
            self.normalLow = normalLow
            self.normalHigh = normalHigh
            self.now = now
            self.normalStart = normalStart
            self.normalWidth = normalWidth
            self.todayStart = todayStart
            self.todayWidth = todayWidth
            self.nowFraction = nowFraction
            self.lowLabelFraction = lowLabelFraction
            self.highLabelFraction = highLabelFraction
            self.captionFraction = captionFraction
        }
    }

    // MARK: - Hero voice

    public static func heroVoice(
        forecast: ForecastResponse,
        conditions: CurrentConditions,
        hourlyNormals: HourlyNormals?,
        tempBand: TempBand?,
        dailyRain: [DailyRainNormal],
        formatter: UnitFormatter
    ) -> HeroVoice? {
        let day = dayOfMonth(conditions.todayString)
        let month = monthName(conditions.todayString)
        let when = "\(monthPart(day))-\(month)"
        let part = dayPart(conditions.currentHour)
        let nowDelta = hourDelta(conditions: conditions, hourlyNormals: hourlyNormals)
        let dayDelta = dayAnomaly(
            dayIndex: conditions.todayIndex, forecast: forecast,
            conditions: conditions, tempBand: tempBand)
        let rainToday = dailyRain.first { $0.date == conditions.todayString }
        let wbNow = conditions.wetBulbNow
        let wbNorm = hourlyNormals?.wetBulb.avgByHour.value(at: conditions.currentHour) ?? nil

        var headline: String?
        var panel = PanelID.temperature
        var rule = "typical"
        if let rainToday, rainToday.p90Mm > 0, rainToday.forecastMm >= rainToday.p90Mm,
           rainToday.forecastMm >= 0.2 {
            headline = "An unusually wet day for \(when)"
            panel = .rain
            rule = "rain"
        } else if let nowDelta, abs(nowDelta) >= 2, let words = degreeWords(nowDelta, formatter: formatter) {
            headline = "\(words) than a normal \(when) \(part)"
            rule = "now"
        } else if let dayDelta, abs(dayDelta) >= 2, let words = degreeWords(dayDelta, formatter: formatter) {
            headline = "\(words) than a normal \(when) day"
            rule = "day"
        } else if let wbNow, wbNow >= 16, let wbNorm, wbNorm >= 8 {
            let pct = ((wbNow - wbNorm) / wbNorm) * 100
            if abs(pct) >= 15 {
                headline = pct > 0
                    ? "Much muggier than usual for the time of day"
                    : "Much less muggy than usual for the time of day"
                panel = .wetBulb
                rule = "wb"
            }
        }
        if headline == nil {
            if dayDelta == nil, nowDelta == nil { return nil }
            headline = "A typical \(when) \(part)"
            rule = "typical"
        }

        var clauses: [String] = []
        if rule == "typical" {
            let tempClose = nowDelta == nil || abs(nowDelta!) < 1
            let wbClose = wbNow == nil || wbNorm == nil || abs(wbNow! - wbNorm!) < 1
            clauses.append(tempClose && wbClose
                ? "Temperature and humidity within 1° of the usual"
                : "Temperature within 1° of the usual")
        }
        if hourlyNormals != nil, let extreme = weekExtreme(
            forecast: forecast, conditions: conditions, part: part) {
            clauses.append(extreme)
        }
        if rule != "typical" {
            let daily = forecast.daily
            for index in (conditions.todayIndex + 1)..<daily.time.count {
                guard let anomaly = dayAnomaly(
                    dayIndex: index, forecast: forecast, conditions: conditions, tempBand: tempBand),
                      abs(anomaly) <= 1
                else { continue }
                clauses.append("Back to average by \(weekday(daily.time[index], timeZone: forecast.locationTimeZone))")
                break
            }
        }
        return HeroVoice(
            headline: headline ?? "",
            detail: clauses.prefix(2).joined(separator: " · "),
            panel: panel)
    }

    // MARK: - Rain outlook

    public static func rainOutlook(
        forecast: ForecastResponse, conditions: CurrentConditions, formatter: UnitFormatter
    ) -> RainOutlook {
        let hourly = forecast.hourly
        guard !hourly.time.isEmpty else {
            return RainOutlook(
                state: .dry, headline: "No rain in the forecast", detail: nil,
                heroValue: "—", hourlyChance: [], prominent: false)
        }
        let now = conditions.nowIndex
        let chances = (now..<min(hourly.time.count, now + 24)).map {
            hourly.precipitationProbability.value(at: $0) ?? 0
        }
        var wet = -1
        for index in now..<min(hourly.time.count, now + 48) {
            if (hourly.precipitation.value(at: index) ?? 0) >= 0.2 {
                wet = index
                break
            }
        }
        if wet == now {
            let mm = hourly.precipitation.value(at: now) ?? 0
            return RainOutlook(
                state: .rainingNow,
                headline: "\(precipWord(forecast: forecast, hourIndex: now)) this hour",
                detail: "About ~\(formatter.precipitation(mm)) this hour",
                heroValue: "Now",
                hourlyChance: chances,
                prominent: true)
        }
        if wet > now {
            let stamp = hourly.time[wet]
            let date = String(stamp.prefix(10))
            let hour = hourOf(stamp)
            let word = precipWord(forecast: forecast, hourIndex: wet).lowercased()
            let hoursAway = wet - now
            if date == conditions.todayString {
                let mm = sumUntilEndOfDay(forecast: forecast, from: wet, date: date)
                return RainOutlook(
                    state: .laterToday,
                    headline: "Dry until about \(hourClock(hour))",
                    detail: "Then \(word), ~\(formatter.precipitation(mm)) by midnight",
                    heroValue: "Until \(hourClock(hour))",
                    hourlyChance: chances,
                    prominent: hoursAway <= 3)
            }
            let zone = forecast.locationTimeZone
            let day = weekday(date, timeZone: zone)
            let short = weekday(date, timeZone: zone, short: true)
            let dayIndex = forecast.daily.time.firstIndex(of: date) ?? -1
            let dayMm = dayIndex >= 0
                ? (forecast.daily.precipitationSum.value(at: dayIndex) ?? 0)
                : (hourly.precipitation.value(at: wet) ?? 0)
            return RainOutlook(
                state: .laterToday,
                headline: "Dry until \(day) \(dayPart(hour))",
                detail: "Then \(word), ~\(formatter.precipitation(dayMm))",
                heroValue: "Dry until \(short)",
                hourlyChance: chances,
                prominent: false)
        }
        let windowStart = max(0, now - 24)
        let windowEnd = min(hourly.time.count, now + 24)
        let allDry = (windowStart..<windowEnd).allSatisfy {
            (hourly.precipitation.value(at: $0) ?? 0) < 0.05
        }
        let next = nextDailyWet(forecast: forecast, after: conditions.todayString)
        let detail = next.map {
            "Next: \(weekday($0.date, timeZone: forecast.locationTimeZone)), ~\(formatter.precipitation($0.mm))"
        } ?? "No rain in the 7-day forecast"
        let hero = next.map {
            "Dry until \(weekday($0.date, timeZone: forecast.locationTimeZone, short: true))"
        } ?? "Dry"
        return RainOutlook(
            state: .dry,
            headline: allDry ? "No rain for at least 48 hours" : "No rain for at least 24 hours",
            detail: detail,
            heroValue: hero,
            hourlyChance: chances,
            prominent: false)
    }

    public struct RainWindowTotals: Equatable, Sendable {
        public let last7: Double
        public let lastNormal: Double?
        public let next7: Double
        public let nextNormal: Double?

        public init(last7: Double, lastNormal: Double?, next7: Double, nextNormal: Double?) {
            self.last7 = last7
            self.lastNormal = lastNormal
            self.next7 = next7
            self.nextNormal = nextNormal
        }
    }

    public struct UpdatedPhrase: Equatable, Sendable {
        public let text: String
        /// True when the forecast was fetched today and is under three hours old.
        public let live: Bool

        public init(text: String, live: Bool) {
            self.text = text
            self.live = live
        }
    }

    /// Last 7 days and the next 7 days of Open-Meteo daily totals.
    /// Month-to-date is omitted: the archive model has no month-to-date field.
    public static func rainTotals(
        forecast: ForecastResponse, conditions: CurrentConditions, dailyRain: [DailyRainNormal]
    ) -> RainWindowTotals {
        let daily = forecast.daily
        let today = conditions.todayIndex
        let lastStart = max(0, today - 7)
        let nextEnd = min(daily.time.count, today + 7)
        var byDate: [String: Double] = [:]
        for row in dailyRain { byDate[row.date] = row.histMeanMm }
        func sum(_ range: Range<Int>, normal: Bool) -> Double {
            range.reduce(0) { partial, index in
                let date = daily.time[index]
                if normal { return partial + (byDate[date] ?? 0) }
                return partial + (daily.precipitationSum.value(at: index) ?? 0)
            }
        }
        return RainWindowTotals(
            last7: sum(lastStart..<today, normal: false),
            lastNormal: dailyRain.isEmpty ? nil : sum(lastStart..<today, normal: true),
            next7: sum(today..<nextEnd, normal: false),
            nextNormal: dailyRain.isEmpty ? nil : sum(today..<nextEnd, normal: true))
    }

    /// Location-local "Updated HH:MM", matching the website pin.
    public static func updatedPhrase(
        fetchedAt: Date?, now: Date, timeZone: TimeZone
    ) -> UpdatedPhrase {
        guard let fetchedAt else { return UpdatedPhrase(text: "Updated —", live: false) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US")
        let clock = calendar.dateComponents([.hour, .minute], from: fetchedAt)
        let hm = String(format: "%02d:%02d", clock.hour ?? 0, clock.minute ?? 0)
        let age = now.timeIntervalSince(fetchedAt)
        if age < 3 * 3600, calendar.isDate(fetchedAt, inSameDayAs: now) {
            return UpdatedPhrase(text: "Updated \(hm)", live: true)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(fetchedAt, inSameDayAs: yesterday) {
            return UpdatedPhrase(text: "Updated yesterday \(hm)", live: false)
        }
        let day = calendar.component(.day, from: fetchedAt)
        let month = calendar.shortMonthSymbols[calendar.component(.month, from: fetchedAt) - 1]
        return UpdatedPhrase(text: "Updated \(day) \(month) \(hm)", live: false)
    }

    public static func wetBulbHiddenDetail(
        conditions: CurrentConditions, hourlyNormals: HourlyNormals?, formatter: UnitFormatter
    ) -> String {
        guard let now = conditions.wetBulbNow,
              let norm = hourlyNormals?.wetBulb.avgByHour.value(at: conditions.currentHour) ?? nil
        else { return "Charts hidden while it stays under 15°." }
        let delta = now - norm
        let shown = Int(formatter.temperatureDelta(abs(delta)).rounded())
        let side = delta < 0 ? "below" : "above"
        return "\(shown)° \(side) the usual for the hour. Charts hidden while it stays under 15°."
    }

    public static func maxWetBulb(_ forecast: ForecastResponse) -> Double? {
        let values = forecast.daily.wetBulbTemperature2mMax + forecast.hourly.wetBulbTemperature2m
        let finite = values.compactMap { $0 }
        return finite.max()
    }

    // MARK: - Normal range

    public static func todayRange(
        conditions: CurrentConditions, normal: DayNormal?
    ) -> TodayRange? {
        guard let low = conditions.low, let high = conditions.high,
              let normalLow = normal?.tMin, let normalHigh = normal?.tMax
        else { return nil }
        let pad = 3.0
        var values = [low, high, normalLow, normalHigh]
        if let now = conditions.temperature { values.append(now) }
        let minV = (values.min() ?? low) - pad
        let maxV = (values.max() ?? high) + pad
        let span = max(maxV - minV, 1)
        func pct(_ value: Double) -> Double { (value - minV) / span }
        let n1 = pct(min(normalLow, normalHigh))
        let n2 = pct(max(normalLow, normalHigh))
        let t1 = pct(min(low, high))
        let t2 = pct(max(low, high))
        var l1 = t1
        var l2 = t2
        if l2 - l1 < 0.18 {
            let mid = (l1 + l2) / 2
            l1 = mid - 0.10
            l2 = mid + 0.10
        }
        l1 = min(0.92, max(0.08, l1))
        l2 = min(0.92, max(0.08, l2))
        return TodayRange(
            low: low, high: high, normalLow: normalLow, normalHigh: normalHigh,
            now: conditions.temperature,
            normalStart: n1, normalWidth: max(n2 - n1, 0.01),
            todayStart: t1, todayWidth: max(t2 - t1, 0.012),
            nowFraction: conditions.temperature.map(pct),
            lowLabelFraction: l1, highLabelFraction: l2,
            captionFraction: (n1 + n2) / 2)
    }

    public static func shortPlaceName(_ name: String) -> String {
        let parts = name.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if parts.count >= 2, parts[0].caseInsensitiveCompare(parts[1]) == .orderedSame {
            return parts[0]
        }
        if parts.count >= 2 { return "\(parts[0]), \(parts[1])" }
        return name
    }

    // MARK: - Words

    static func monthPart(_ day: Int) -> String {
        if day <= 10 { return "early" }
        if day <= 20 { return "mid" }
        return "late"
    }

    static func dayPart(_ hour: Int) -> String {
        if (5..<12).contains(hour) { return "morning" }
        if (12..<18).contains(hour) { return "afternoon" }
        if (18..<22).contains(hour) { return "evening" }
        return "overnight"
    }

    static func hourClock(_ hour: Int) -> String {
        switch hour {
        case 0, 24: return "12am"
        case 12: return "12pm"
        case ..<12: return "\(hour)am"
        default: return "\(hour - 12)pm"
        }
    }

    static func degreeWords(_ deltaC: Double, formatter: UnitFormatter) -> String? {
        let shown = Int(formatter.temperatureDelta(abs(deltaC)).rounded())
        if abs(deltaC) < 1 || shown < 1 { return nil }
        return "\(shown)° \(deltaC > 0 ? "warmer" : "colder")"
    }

    // MARK: - Private

    private static func hourDelta(
        conditions: CurrentConditions, hourlyNormals: HourlyNormals?
    ) -> Double? {
        guard let temp = conditions.temperature,
              let norm = hourlyNormals?.temp.avgByHour.value(at: conditions.currentHour) ?? nil
        else { return nil }
        return temp - norm
    }

    private static func dayAnomaly(
        dayIndex: Int, forecast: ForecastResponse, conditions: CurrentConditions, tempBand: TempBand?
    ) -> Double? {
        let bandIndex = dayIndex - conditions.todayIndex + 7
        guard let band = tempBand?.dailyAvg.at(bandIndex) ?? nil,
              let histMax = band.tMax, let histMin = band.tMin,
              let high = forecast.daily.temperature2mMax.value(at: dayIndex),
              let low = forecast.daily.temperature2mMin.value(at: dayIndex)
        else { return nil }
        return (high + low) / 2 - (histMax + histMin) / 2
    }

    private static func weekExtreme(
        forecast: ForecastResponse, conditions: CurrentConditions, part: String
    ) -> String? {
        guard let tempNow = conditions.temperature else { return nil }
        let hourly = forecast.hourly
        var same: [Double] = []
        for index in hourly.time.indices {
            let stamp = hourly.time[index]
            guard hourOf(stamp) == conditions.currentHour else { continue }
            guard String(stamp.prefix(10)) <= conditions.todayString else { continue }
            if let value = hourly.temperature2m.value(at: index) { same.append(value) }
        }
        guard same.count >= 3, let low = same.min(), let high = same.max() else { return nil }
        if tempNow <= low + 0.05 { return "Coldest \(part) this week" }
        if tempNow >= high - 0.05 { return "Warmest \(part) this week" }
        return nil
    }

    private static func precipWord(forecast: ForecastResponse, hourIndex: Int) -> String {
        let code = forecast.hourly.weatherCode.value(at: hourIndex) ?? 0
        if code >= 96 { return "Hail" }
        if code == 56 || code == 57 || code == 66 || code == 67 { return "Sleet" }
        let snow = forecast.hourly.snowfall.value(at: hourIndex) ?? 0
        let rain = (forecast.hourly.rain.value(at: hourIndex) ?? 0) + (forecast.hourly.showers.value(at: hourIndex) ?? 0)
        if (snow > rain && snow >= 0.05) || (71...86).contains(code) { return "Snow" }
        return "Rain"
    }

    private static func sumUntilEndOfDay(
        forecast: ForecastResponse, from index: Int, date: String
    ) -> Double {
        var sum = 0.0
        for cursor in index..<forecast.hourly.time.count {
            guard String(forecast.hourly.time[cursor].prefix(10)) == date else { break }
            sum += forecast.hourly.precipitation.value(at: cursor) ?? 0
        }
        return sum
    }

    private static func nextDailyWet(
        forecast: ForecastResponse, after date: String
    ) -> (date: String, mm: Double)? {
        for index in forecast.daily.time.indices {
            let day = forecast.daily.time[index]
            guard day > date else { continue }
            let mm = forecast.daily.precipitationSum.value(at: index) ?? 0
            if mm >= 0.2 { return (day, mm) }
        }
        return nil
    }

    private static func dayOfMonth(_ date: String) -> Int {
        Int(date.dropFirst(8)) ?? 1
    }

    private static func monthName(_ date: String) -> String {
        let names = [
            "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        let month = Int(date.dropFirst(5).prefix(2)) ?? 1
        return names[max(0, min(11, month - 1))]
    }

    private static func hourOf(_ stamp: String) -> Int {
        guard stamp.count >= 13 else { return 0 }
        let start = stamp.index(stamp.startIndex, offsetBy: 11)
        let end = stamp.index(start, offsetBy: 2)
        return Int(stamp[start..<end]) ?? 0
    }

    private static func weekday(_ date: String, timeZone: TimeZone, short: Bool = false) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed = parser.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = timeZone
        formatter.dateFormat = short ? "EEE" : "EEEE"
        return formatter.string(from: parsed)
    }
}
