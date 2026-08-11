import Foundation

/// Decoded `https://api.open-meteo.com/v1/forecast` response.
///
/// Time strings are **location-local wall time with no timezone suffix**
/// (`"2026-08-05"` / `"2026-08-05T14:00"`). They are deliberately kept as
/// `String` — all index lookups are string comparisons against strings built
/// from "now in the location's timezone" (see `CurrentConditions`). Parsing them
/// into `Date` for indexing is how off-by-one timezone bugs get in.
///
/// Every value array decodes as `[Double?]`/`[Int?]` because Open-Meteo returns
/// `null` for missing values.
public struct ForecastResponse: Codable, Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let timezone: String
    public let timezoneAbbreviation: String?
    public let utcOffsetSeconds: Int
    public let daily: Daily
    public let hourly: Hourly

    public init(
        latitude: Double,
        longitude: Double,
        timezone: String,
        timezoneAbbreviation: String? = nil,
        utcOffsetSeconds: Int,
        daily: Daily,
        hourly: Hourly
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
        self.timezoneAbbreviation = timezoneAbbreviation
        self.utcOffsetSeconds = utcOffsetSeconds
        self.daily = daily
        self.hourly = hourly
    }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone, daily, hourly
        case timezoneAbbreviation = "timezone_abbreviation"
        case utcOffsetSeconds = "utc_offset_seconds"
    }

    /// The forecast location's timezone, resolved from the API's `timezone`
    /// identifier with the reported UTC offset as a fallback.
    ///
    /// PLAN DEVIATION §1.4.2: all "now" arithmetic happens here, not in the
    /// device timezone, so a searched location on the other side of the world
    /// reports *its* current hour.
    public var locationTimeZone: TimeZone {
        TimeZone(identifier: timezone)
            ?? TimeZone(secondsFromGMT: utcOffsetSeconds)
            ?? .gmt
    }

    public struct Daily: Codable, Sendable, Equatable {
        /// `"YYYY-MM-DD"`, location-local. 14 entries (past_days 7 + forecast_days 7).
        public let time: [String]
        public let weatherCode: [Int?]
        public let temperature2mMax: [Double?]
        public let temperature2mMin: [Double?]
        public let wetBulbTemperature2mMax: [Double?]
        public let wetBulbTemperature2mMin: [Double?]
        public let apparentTemperatureMax: [Double?]
        public let precipitationSum: [Double?]
        public let precipitationProbabilityMax: [Int?]
        public let windSpeed10mMax: [Double?]
        public let uvIndexMax: [Double?]
        /// `"YYYY-MM-DDTHH:mm"`, location-local, like every other time string.
        public let sunrise: [String?]
        public let sunset: [String?]

        public init(
            time: [String],
            weatherCode: [Int?] = [],
            temperature2mMax: [Double?] = [],
            temperature2mMin: [Double?] = [],
            wetBulbTemperature2mMax: [Double?] = [],
            wetBulbTemperature2mMin: [Double?] = [],
            apparentTemperatureMax: [Double?] = [],
            precipitationSum: [Double?] = [],
            precipitationProbabilityMax: [Int?] = [],
            windSpeed10mMax: [Double?] = [],
            uvIndexMax: [Double?] = [],
            sunrise: [String?] = [],
            sunset: [String?] = []
        ) {
            self.time = time
            self.weatherCode = weatherCode
            self.temperature2mMax = temperature2mMax
            self.temperature2mMin = temperature2mMin
            self.wetBulbTemperature2mMax = wetBulbTemperature2mMax
            self.wetBulbTemperature2mMin = wetBulbTemperature2mMin
            self.apparentTemperatureMax = apparentTemperatureMax
            self.precipitationSum = precipitationSum
            self.precipitationProbabilityMax = precipitationProbabilityMax
            self.windSpeed10mMax = windSpeed10mMax
            self.uvIndexMax = uvIndexMax
            self.sunrise = sunrise
            self.sunset = sunset
        }

        enum CodingKeys: String, CodingKey {
            case time, sunrise, sunset
            case weatherCode = "weather_code"
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case wetBulbTemperature2mMax = "wet_bulb_temperature_2m_max"
            case wetBulbTemperature2mMin = "wet_bulb_temperature_2m_min"
            case apparentTemperatureMax = "apparent_temperature_max"
            case precipitationSum = "precipitation_sum"
            case precipitationProbabilityMax = "precipitation_probability_max"
            case windSpeed10mMax = "wind_speed_10m_max"
            case uvIndexMax = "uv_index_max"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            time = try c.decode([String].self, forKey: .time)
            weatherCode = try c.decodeIfPresent([Int?].self, forKey: .weatherCode) ?? []
            temperature2mMax = try c.decodeIfPresent([Double?].self, forKey: .temperature2mMax) ?? []
            temperature2mMin = try c.decodeIfPresent([Double?].self, forKey: .temperature2mMin) ?? []
            wetBulbTemperature2mMax = try c.decodeIfPresent([Double?].self, forKey: .wetBulbTemperature2mMax) ?? []
            wetBulbTemperature2mMin = try c.decodeIfPresent([Double?].self, forKey: .wetBulbTemperature2mMin) ?? []
            apparentTemperatureMax = try c.decodeIfPresent([Double?].self, forKey: .apparentTemperatureMax) ?? []
            precipitationSum = try c.decodeIfPresent([Double?].self, forKey: .precipitationSum) ?? []
            precipitationProbabilityMax = try c.decodeIfPresent([Int?].self, forKey: .precipitationProbabilityMax) ?? []
            windSpeed10mMax = try c.decodeIfPresent([Double?].self, forKey: .windSpeed10mMax) ?? []
            uvIndexMax = try c.decodeIfPresent([Double?].self, forKey: .uvIndexMax) ?? []
            sunrise = try c.decodeIfPresent([String?].self, forKey: .sunrise) ?? []
            sunset = try c.decodeIfPresent([String?].self, forKey: .sunset) ?? []
        }
    }

    public struct Hourly: Codable, Sendable, Equatable {
        /// `"YYYY-MM-DDTHH:mm"`, location-local, no timezone suffix.
        public let time: [String]
        public let temperature2m: [Double?]
        public let wetBulbTemperature2m: [Double?]
        public let apparentTemperature: [Double?]
        public let precipitation: [Double?]
        public let precipitationProbability: [Int?]
        public let rain: [Double?]
        public let showers: [Double?]
        public let snowfall: [Double?]
        public let weatherCode: [Int?]
        /// PLAN DEVIATION §1.4.1: requested in addition to the web app so the
        /// condition symbol can pick a night variant.
        public let isDay: [Int?]

        public init(
            time: [String],
            temperature2m: [Double?] = [],
            wetBulbTemperature2m: [Double?] = [],
            apparentTemperature: [Double?] = [],
            precipitation: [Double?] = [],
            precipitationProbability: [Int?] = [],
            rain: [Double?] = [],
            showers: [Double?] = [],
            snowfall: [Double?] = [],
            weatherCode: [Int?] = [],
            isDay: [Int?] = []
        ) {
            self.time = time
            self.temperature2m = temperature2m
            self.wetBulbTemperature2m = wetBulbTemperature2m
            self.apparentTemperature = apparentTemperature
            self.precipitation = precipitation
            self.precipitationProbability = precipitationProbability
            self.rain = rain
            self.showers = showers
            self.snowfall = snowfall
            self.weatherCode = weatherCode
            self.isDay = isDay
        }

        enum CodingKeys: String, CodingKey {
            case time, precipitation, rain, showers, snowfall
            case temperature2m = "temperature_2m"
            case wetBulbTemperature2m = "wet_bulb_temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case precipitationProbability = "precipitation_probability"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            time = try c.decode([String].self, forKey: .time)
            temperature2m = try c.decodeIfPresent([Double?].self, forKey: .temperature2m) ?? []
            wetBulbTemperature2m = try c.decodeIfPresent([Double?].self, forKey: .wetBulbTemperature2m) ?? []
            apparentTemperature = try c.decodeIfPresent([Double?].self, forKey: .apparentTemperature) ?? []
            precipitation = try c.decodeIfPresent([Double?].self, forKey: .precipitation) ?? []
            precipitationProbability = try c.decodeIfPresent([Int?].self, forKey: .precipitationProbability) ?? []
            rain = try c.decodeIfPresent([Double?].self, forKey: .rain) ?? []
            showers = try c.decodeIfPresent([Double?].self, forKey: .showers) ?? []
            snowfall = try c.decodeIfPresent([Double?].self, forKey: .snowfall) ?? []
            weatherCode = try c.decodeIfPresent([Int?].self, forKey: .weatherCode) ?? []
            isDay = try c.decodeIfPresent([Int?].self, forKey: .isDay) ?? []
        }
    }
}
