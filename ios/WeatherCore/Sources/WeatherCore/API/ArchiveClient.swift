import Foundation

/// The three archive requests (§4.2). Every call goes through `ArchiveThrottler`.
public struct ArchiveClient: Sendable {
    public static let host = "archive-api.open-meteo.com"

    private let throttler: ArchiveThrottler

    public init(throttler: ArchiveThrottler) {
        self.throttler = throttler
    }

    static func url(
        latitude: Double,
        longitude: Double,
        startDate: String,
        endDate: String,
        daily: [String] = [],
        hourly: [String] = []
    ) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v1/archive"
        var items = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "start_date", value: startDate),
            URLQueryItem(name: "end_date", value: endDate)
        ]
        if !daily.isEmpty {
            items.append(URLQueryItem(name: "daily", value: daily.joined(separator: ",")))
        }
        if !hourly.isEmpty {
            items.append(URLQueryItem(name: "hourly", value: hourly.joined(separator: ",")))
        }
        components.queryItems = items
        return components.url!
    }

    // MARK: - (a) Climatology: 10 years of daily data, one request (§4.2a)

    static let climatologyVariables = [
        "temperature_2m_max",
        "temperature_2m_min",
        "wet_bulb_temperature_2m_max",
        "wet_bulb_temperature_2m_min",
        "precipitation_sum"
    ]

    public static func climatologyURL(
        latitude: Double, longitude: Double, thisYear: Int
    ) -> URL {
        url(
            latitude: latitude, longitude: longitude,
            startDate: "\(thisYear - 10)-01-01",
            endDate: "\(thisYear - 1)-12-31",
            daily: climatologyVariables
        )
    }

    public func climatology(
        latitude: Double, longitude: Double, thisYear: Int
    ) async throws -> ArchiveResponse {
        try await throttler.fetch(
            ArchiveResponse.self,
            from: Self.climatologyURL(latitude: latitude, longitude: longitude, thisYear: thisYear))
    }

    // MARK: - (b) Hourly normals: ±7 days in each of the last 5 years (§4.2b)

    static let hourlyNormalsVariables = [
        "temperature_2m",
        "wet_bulb_temperature_2m",
        "precipitation"
    ]

    /// One URL per year `i` in 1…5, windowed (today − 7) … (today + 7) of `thisYear − i`.
    public static func hourlyNormalsURLs(
        latitude: Double, longitude: Double, now: Date, dateKit: DateKit
    ) -> [URL] {
        let thisYear = dateKit.year(now)
        let month = dateKit.month(now)
        let day = dateKit.day(now)
        return (1...5).map { i in
            // `new Date(yr, mo, dy ± 7)` — day overflow rolls the month/year, which
            // Calendar's date(byAdding:) reproduces.
            let anchor = dateKit.noon(year: thisYear - i, month: month, day: day)
            let start = dateKit.dateString(offsetDays: -7, from: anchor)
            let end = dateKit.dateString(offsetDays: 7, from: anchor)
            return url(
                latitude: latitude, longitude: longitude,
                startDate: start, endDate: end,
                hourly: hourlyNormalsVariables)
        }
    }

    /// Fetches all five windows concurrently (the throttler caps them at 3 in
    /// flight). Individual failures degrade to `nil` exactly like the web app's
    /// `.catch(() => null)`.
    public func hourlyNormalWindows(
        latitude: Double, longitude: Double, now: Date, dateKit: DateKit
    ) async -> [ArchiveResponse?] {
        let urls = Self.hourlyNormalsURLs(
            latitude: latitude, longitude: longitude, now: now, dateKit: dateKit)
        let throttler = self.throttler
        return await withTaskGroup(of: (Int, ArchiveResponse?).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let response = try? await throttler.fetch(ArchiveResponse.self, from: url)
                    return (index, response)
                }
            }
            var results = [ArchiveResponse?](repeating: nil, count: urls.count)
            for await (index, response) in group {
                results[index] = response
            }
            return results
        }
    }

    // MARK: - (c) Year-to-date rain: 2000 → today, one request (§4.2c)

    public static func ytdRainURL(
        latitude: Double, longitude: Double, todayString: String, startYear: Int = 2000
    ) -> URL {
        url(
            latitude: latitude, longitude: longitude,
            startDate: "\(startYear)-01-01",
            endDate: todayString,
            daily: ["precipitation_sum"]
        )
    }

    public func ytdRain(
        latitude: Double, longitude: Double, todayString: String, startYear: Int = 2000
    ) async throws -> ArchiveResponse {
        try await throttler.fetch(
            ArchiveResponse.self,
            from: Self.ytdRainURL(
                latitude: latitude, longitude: longitude,
                todayString: todayString, startYear: startYear))
    }
}
