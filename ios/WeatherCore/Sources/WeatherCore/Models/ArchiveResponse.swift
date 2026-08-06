import Foundation

/// Decoded `https://archive-api.open-meteo.com/v1/archive` response.
///
/// One type covers all three archive calls (§4.2a climatology, §4.2b hourly
/// normals, §4.2c YTD rain); each populates a different subset of the arrays.
///
/// The most recent 2–5 days are routinely missing or `null` — that is the
/// archive's publication lag, not a decoding failure (§14.3).
public struct ArchiveResponse: Codable, Sendable, Equatable {
    public let latitude: Double
    public let longitude: Double
    public let timezone: String?
    public let utcOffsetSeconds: Int?
    public let daily: Daily?
    public let hourly: Hourly?

    public init(
        latitude: Double = 0,
        longitude: Double = 0,
        timezone: String? = nil,
        utcOffsetSeconds: Int? = nil,
        daily: Daily? = nil,
        hourly: Hourly? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
        self.utcOffsetSeconds = utcOffsetSeconds
        self.daily = daily
        self.hourly = hourly
    }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, timezone, daily, hourly
        case utcOffsetSeconds = "utc_offset_seconds"
    }

    public struct Daily: Codable, Sendable, Equatable {
        public let time: [String]
        public let temperature2mMax: [Double?]
        public let temperature2mMin: [Double?]
        public let wetBulbTemperature2mMax: [Double?]
        public let wetBulbTemperature2mMin: [Double?]
        public let precipitationSum: [Double?]

        public init(
            time: [String],
            temperature2mMax: [Double?] = [],
            temperature2mMin: [Double?] = [],
            wetBulbTemperature2mMax: [Double?] = [],
            wetBulbTemperature2mMin: [Double?] = [],
            precipitationSum: [Double?] = []
        ) {
            self.time = time
            self.temperature2mMax = temperature2mMax
            self.temperature2mMin = temperature2mMin
            self.wetBulbTemperature2mMax = wetBulbTemperature2mMax
            self.wetBulbTemperature2mMin = wetBulbTemperature2mMin
            self.precipitationSum = precipitationSum
        }

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case wetBulbTemperature2mMax = "wet_bulb_temperature_2m_max"
            case wetBulbTemperature2mMin = "wet_bulb_temperature_2m_min"
            case precipitationSum = "precipitation_sum"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            time = try c.decode([String].self, forKey: .time)
            temperature2mMax = try c.decodeIfPresent([Double?].self, forKey: .temperature2mMax) ?? []
            temperature2mMin = try c.decodeIfPresent([Double?].self, forKey: .temperature2mMin) ?? []
            wetBulbTemperature2mMax = try c.decodeIfPresent([Double?].self, forKey: .wetBulbTemperature2mMax) ?? []
            wetBulbTemperature2mMin = try c.decodeIfPresent([Double?].self, forKey: .wetBulbTemperature2mMin) ?? []
            precipitationSum = try c.decodeIfPresent([Double?].self, forKey: .precipitationSum) ?? []
        }
    }

    public struct Hourly: Codable, Sendable, Equatable {
        public let time: [String]
        public let temperature2m: [Double?]
        public let wetBulbTemperature2m: [Double?]
        public let precipitation: [Double?]

        public init(
            time: [String],
            temperature2m: [Double?] = [],
            wetBulbTemperature2m: [Double?] = [],
            precipitation: [Double?] = []
        ) {
            self.time = time
            self.temperature2m = temperature2m
            self.wetBulbTemperature2m = wetBulbTemperature2m
            self.precipitation = precipitation
        }

        enum CodingKeys: String, CodingKey {
            case time, precipitation
            case temperature2m = "temperature_2m"
            case wetBulbTemperature2m = "wet_bulb_temperature_2m"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            time = try c.decode([String].self, forKey: .time)
            temperature2m = try c.decodeIfPresent([Double?].self, forKey: .temperature2m) ?? []
            wetBulbTemperature2m = try c.decodeIfPresent([Double?].self, forKey: .wetBulbTemperature2m) ?? []
            precipitation = try c.decodeIfPresent([Double?].self, forKey: .precipitation) ?? []
        }
    }
}
