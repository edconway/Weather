import Foundation

/// Fetch-or-cache for every piece of data the UI needs (§7.2).
///
/// Deliberately *not* a state machine: each method returns one value, and the
/// caller (a store) decides ordering, cancellation and staleness guards. That
/// keeps the location-switch race (§14.9) in one place instead of two.
public actor WeatherRepository {
    /// A value plus whether it came from a cache entry past its TTL.
    public struct Fetched<Value: Sendable>: Sendable {
        public let value: Value
        public let isStale: Bool
        public let savedAt: Date?

        public init(value: Value, isStale: Bool, savedAt: Date? = nil) {
            self.value = value
            self.isStale = isStale
            self.savedAt = savedAt
        }
    }

    private let forecastClient: OpenMeteoClient
    private let archiveClient: ArchiveClient
    private let cache: DiskCache
    private let clock: @Sendable () -> Date

    public init(
        forecastClient: OpenMeteoClient = OpenMeteoClient(),
        archiveClient: ArchiveClient = ArchiveClient(throttler: ArchiveThrottler()),
        cache: DiskCache = DiskCache(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.forecastClient = forecastClient
        self.archiveClient = archiveClient
        self.cache = cache
        self.clock = clock
    }

    public var diskCache: DiskCache { cache }

    // MARK: - Forecast

    /// Fresh cache → network → stale cache. The last step is what keeps the app
    /// usable in airplane mode with a warm cache (§11.3).
    public func forecast(for location: WeatherLocation) async throws -> Fetched<ForecastResponse> {
        if let cached = await cache.readFresh(
            ForecastResponse.self, kind: .forecast, location: location) {
            return Fetched(value: cached, isStale: false)
        }

        do {
            let response = try await forecastClient.forecast(
                latitude: location.latitude, longitude: location.longitude)
            await cache.write(response, kind: .forecast, location: location)
            await cache.write(location, kind: .lastLocation)
            return Fetched(value: response, isStale: false)
        } catch {
            if let hit = await cache.read(
                ForecastResponse.self, kind: .forecast, location: location) {
                return Fetched(value: hit.value, isStale: true, savedAt: hit.savedAt)
            }
            throw error
        }
    }

    /// Bypasses the cache — used by background refresh, which exists precisely
    /// to replace a still-fresh entry before it expires.
    @discardableResult
    public func refreshForecast(for location: WeatherLocation) async throws -> ForecastResponse {
        let response = try await forecastClient.forecast(
            latitude: location.latitude, longitude: location.longitude)
        await cache.write(response, kind: .forecast, location: location)
        await cache.write(location, kind: .lastLocation)
        return response
    }

    // MARK: - Hourly normals (§6.6)

    public func hourlyNormals(
        for location: WeatherLocation, now: Date, timeZone: TimeZone
    ) async throws -> HourlyNormals {
        if let cached = await cache.readFresh(
            HourlyNormals.self, kind: .hourlyNormals, location: location) {
            return cached
        }
        let dateKit = DateKit(timeZone: timeZone)
        let windows = await archiveClient.hourlyNormalWindows(
            latitude: location.latitude, longitude: location.longitude,
            now: now, dateKit: dateKit)
        guard windows.contains(where: { $0 != nil }) else {
            throw WeatherError.network("Historical hourly data is unavailable right now.")
        }
        let normals = HourlyNormalsBuilder.build(
            windows: windows, thisYear: dateKit.year(now))
        await cache.write(normals, kind: .hourlyNormals, location: location)
        return normals
    }

    // MARK: - Climatology (§6.3)

    public func climatology(
        for location: WeatherLocation, now: Date, timeZone: TimeZone
    ) async throws -> Climatology {
        if let cached = await cache.readFresh(
            Climatology.self, kind: .climatology, location: location) {
            return cached
        }
        let thisYear = DateKit(timeZone: timeZone).year(now)
        let response = try await archiveClient.climatology(
            latitude: location.latitude, longitude: location.longitude, thisYear: thisYear)
        guard let climatology = ClimatologyBuilder.build(
            response: response, thisYear: thisYear) else {
            throw WeatherError.network("Historical climate data is unavailable right now.")
        }
        // Only the derived blob is cached; the raw 10-year response is ~1 MB (§7.1).
        await cache.write(climatology, kind: .climatology, location: location)
        return climatology
    }

    // MARK: - Year-to-date rain (§6.7)

    public func ytdRain(
        for location: WeatherLocation, now: Date, timeZone: TimeZone
    ) async throws -> YTDRain {
        if let cached = await cache.readFresh(
            YTDRain.self, kind: .ytdRain, location: location) {
            return cached
        }
        let dateKit = DateKit(timeZone: timeZone)
        let response = try await archiveClient.ytdRain(
            latitude: location.latitude, longitude: location.longitude,
            todayString: dateKit.dateString(now))
        guard let ytd = YTDRainBuilder.build(
            response: response, now: now, timeZone: timeZone) else {
            throw WeatherError.network("Year-to-date rainfall is unavailable right now.")
        }
        await cache.write(ytd, kind: .ytdRain, location: location)
        return ytd
    }

    // MARK: - Last location

    public func lastLocation() async -> WeatherLocation? {
        await cache.readFresh(WeatherLocation.self, kind: .lastLocation)
    }

    public func rememberLastLocation(_ location: WeatherLocation) async {
        await cache.write(location, kind: .lastLocation)
    }
}
