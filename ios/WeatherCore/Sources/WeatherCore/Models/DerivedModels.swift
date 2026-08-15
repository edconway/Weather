import Foundation

// MARK: - Climatology (§6.3)

/// Pool of every archive year's values for one calendar day (`"MM-DD"`).
public struct DayPool: Codable, Sendable, Equatable {
    public var maxes: [Double] = []
    public var mins: [Double] = []
    public var wbMaxes: [Double] = []
    public var wbMins: [Double] = []
    public var rains: [Double] = []

    public init(
        maxes: [Double] = [], mins: [Double] = [], wbMaxes: [Double] = [],
        wbMins: [Double] = [], rains: [Double] = []
    ) {
        self.maxes = maxes
        self.mins = mins
        self.wbMaxes = wbMaxes
        self.wbMins = wbMins
        self.rains = rains
    }
}

/// One calendar month's normals, averaged across the archive years.
public struct MonthNormal: Codable, Sendable, Equatable {
    public let tMax: Double?
    public let tMin: Double?
    public let rain: Double?

    public init(tMax: Double?, tMin: Double?, rain: Double?) {
        self.tMax = tMax
        self.tMin = tMin
        self.rain = rain
    }
}

/// Derived output of the 10-year daily archive request. Cached in place of the
/// ~1 MB raw response (§7.1).
public struct Climatology: Codable, Sendable, Equatable {
    public let months: [MonthNormal]        // 12
    public let byMMDD: [String: DayPool]
    public let yearStart: Int
    public let yearEnd: Int

    public init(months: [MonthNormal], byMMDD: [String: DayPool], yearStart: Int, yearEnd: Int) {
        self.months = months
        self.byMMDD = byMMDD
        self.yearStart = yearStart
        self.yearEnd = yearEnd
    }
}

// MARK: - 14-day temperature band (§6.4)

/// Rolling ±3-day normal for one of the 14 chart days.
public struct DayNormal: Codable, Sendable, Equatable {
    public let tMax: Double?
    public let tMin: Double?
    public let wbMax: Double?
    public let wbMin: Double?

    public init(tMax: Double?, tMin: Double?, wbMax: Double?, wbMin: Double?) {
        self.tMax = tMax
        self.tMin = tMin
        self.wbMax = wbMax
        self.wbMin = wbMin
    }
}

/// `deriveTempBand` output. `dailyAvg` runs today−7 … today+6; index 7 is today.
public struct TempBand: Codable, Sendable, Equatable {
    public let dailyAvg: [DayNormal]        // 14
    public let month: String
    public let histYearStart: Int
    public let histYearEnd: Int

    public init(dailyAvg: [DayNormal], month: String, histYearStart: Int, histYearEnd: Int) {
        self.dailyAvg = dailyAvg
        self.month = month
        self.histYearStart = histYearStart
        self.histYearEnd = histYearEnd
    }

    /// Today's normal — the entry every anomaly and the hero band read from.
    public var today: DayNormal? { dailyAvg.count > 7 ? dailyAvg[7] : nil }
}

// MARK: - Daily rain normals (§6.5)

/// Classification chip shown under each forecast day's bar.
/// Exact thresholds ported from `classifyRain`.
public enum RainClass: String, Codable, Sendable, Equatable {
    case dry = "Dry"
    case heavy = "Heavy"
    case wetter = "Wetter"
    case drier = "Drier"
    case nearAverage = "Near avg"

    public var text: String { rawValue }
}

public struct DailyRainNormal: Codable, Sendable, Equatable {
    public let date: String                 // "YYYY-MM-DD"
    public let forecastMm: Double
    public let probabilityMax: Int?
    public let histMeanMm: Double
    public let histMedianMm: Double
    public let wetDayProbability: Double
    public let p90Mm: Double

    public init(
        date: String, forecastMm: Double, probabilityMax: Int?, histMeanMm: Double,
        histMedianMm: Double, wetDayProbability: Double, p90Mm: Double
    ) {
        self.date = date
        self.forecastMm = forecastMm
        self.probabilityMax = probabilityMax
        self.histMeanMm = histMeanMm
        self.histMedianMm = histMedianMm
        self.wetDayProbability = wetDayProbability
        self.p90Mm = p90Mm
    }

    /// Port of `classifyRain(forecastMm, histMeanMm, p90Mm)`.
    public var classification: RainClass {
        if forecastMm < 0.1 { return .dry }
        if p90Mm > 0 && forecastMm >= p90Mm { return .heavy }
        if forecastMm > histMeanMm * 1.5 && forecastMm - histMeanMm >= 1 { return .wetter }
        if histMeanMm > 0.5 && forecastMm < histMeanMm * 0.5 { return .drier }
        return .nearAverage
    }
}

// MARK: - Hourly normals (§6.6)

public struct HourAverages: Codable, Sendable, Equatable {
    /// 24 entries, index = hour of day. `nil` where no archive sample existed.
    public let avgByHour: [Double?]
    public let yearStart: Int
    public let yearEnd: Int

    public init(avgByHour: [Double?], yearStart: Int, yearEnd: Int) {
        self.avgByHour = avgByHour
        self.yearStart = yearStart
        self.yearEnd = yearEnd
    }
}

public struct RainHourNormals: Codable, Sendable, Equatable {
    /// 24 entries; missing samples count as 0 mm (matches the web app).
    public let avgByHour: [Double]
    public let wetHourProbabilityByHour: [Double]
    public let p90ByHour: [Double]
    public let yearStart: Int
    public let yearEnd: Int

    public init(
        avgByHour: [Double], wetHourProbabilityByHour: [Double], p90ByHour: [Double],
        yearStart: Int, yearEnd: Int
    ) {
        self.avgByHour = avgByHour
        self.wetHourProbabilityByHour = wetHourProbabilityByHour
        self.p90ByHour = p90ByHour
        self.yearStart = yearStart
        self.yearEnd = yearEnd
    }
}

public struct HourlyNormals: Codable, Sendable, Equatable {
    public let temp: HourAverages
    public let wetBulb: HourAverages
    public let rain: RainHourNormals

    public init(temp: HourAverages, wetBulb: HourAverages, rain: RainHourNormals) {
        self.temp = temp
        self.wetBulb = wetBulb
        self.rain = rain
    }
}

// MARK: - Year-to-date rain (§6.7)

public struct YTDRain: Codable, Sendable, Equatable {
    /// `"MM-DD"` from Jan 1 through today.
    public let labels: [String]
    public let cumCurrentYear: [Double]
    public let cumHistAvg: [Double]
    /// Historical-average cumulative extended over the forecast window.
    public let cumHistAvgExt: [Double]
    public let thisYear: Int
    public let startYear: Int
    public let histYears: Int
    /// Last archive date that actually has data — usually 2–5 days behind today.
    public let latestDate: String

    public init(
        labels: [String], cumCurrentYear: [Double], cumHistAvg: [Double],
        cumHistAvgExt: [Double], thisYear: Int, startYear: Int, histYears: Int,
        latestDate: String
    ) {
        self.labels = labels
        self.cumCurrentYear = cumCurrentYear
        self.cumHistAvg = cumHistAvg
        self.cumHistAvgExt = cumHistAvgExt
        self.thisYear = thisYear
        self.startYear = startYear
        self.histYears = histYears
        self.latestDate = latestDate
    }
}

// MARK: - Anomaly badges (§6.8)

public enum AnomalyKind: String, Codable, Sendable, Equatable {
    case warm, cold, wet, dry, muggy, muggyLow, neutral
}

/// Which panel a badge scrolls to when tapped (the web's `data-panel-jump`).
public enum PanelID: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case temperature = "panel-temperature"
    case wetBulb = "panel-wet-bulb"
    case rain = "panel-rain"
    case climate = "panel-climate"
}

public struct Anomaly: Codable, Sendable, Equatable, Identifiable {
    public let text: String
    public let kind: AnomalyKind
    public let panel: PanelID
    /// Longer explanation, shown as an accessibility hint / tooltip.
    public let detail: String?

    public var id: String { "\(panel.rawValue)-\(text)" }

    public init(text: String, kind: AnomalyKind, panel: PanelID, detail: String? = nil) {
        self.text = text
        self.kind = kind
        self.panel = panel
        self.detail = detail
    }
}

// MARK: - Watch sync (§9.2)

/// The small derived blob the phone pushes to the watch. A few KB — the watch
/// never calls the archive API itself.
public struct WatchSyncPayload: Codable, Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let name: String
    public let imperial: Bool
    public let dailyAvg: [DayNormal]        // 14
    public let monthlyNormals: [MonthNormal] // 12
    public let wbAvgByHour: [Double?]       // 24
    /// Hourly temperature normals (24). Optional on decode so older phone
    /// payloads (wet-bulb-only) still load.
    public let tempAvgByHour: [Double?]
    public let generatedAt: Date

    public init(
        latitude: Double, longitude: Double, name: String, imperial: Bool,
        dailyAvg: [DayNormal], monthlyNormals: [MonthNormal], wbAvgByHour: [Double?],
        tempAvgByHour: [Double?] = [], generatedAt: Date
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.imperial = imperial
        self.dailyAvg = dailyAvg
        self.monthlyNormals = monthlyNormals
        self.wbAvgByHour = wbAvgByHour
        self.tempAvgByHour = tempAvgByHour
        self.generatedAt = generatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        name = try c.decode(String.self, forKey: .name)
        imperial = try c.decode(Bool.self, forKey: .imperial)
        dailyAvg = try c.decode([DayNormal].self, forKey: .dailyAvg)
        monthlyNormals = try c.decode([MonthNormal].self, forKey: .monthlyNormals)
        wbAvgByHour = try c.decode([Double?].self, forKey: .wbAvgByHour)
        tempAvgByHour = try c.decodeIfPresent([Double?].self, forKey: .tempAvgByHour) ?? []
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
    }

    public var location: WeatherLocation {
        WeatherLocation(latitude: latitude, longitude: longitude, name: name, source: .custom)
    }
}
