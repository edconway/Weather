import XCTest
@testable import WeatherCore

final class CacheAndPrefsTests: XCTestCase {

    /// Injectable clock so TTLs can be crossed without sleeping.
    final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var now: Date

        init(_ start: Date) { now = start }

        var date: Date {
            lock.lock(); defer { lock.unlock() }
            return now
        }

        func advance(by interval: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            now += interval
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weatherscope-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeCache(_ clock: TestClock) -> DiskCache {
        DiskCache(directory: directory, clock: { clock.date })
    }

    // MARK: - Keys

    /// §7.1, §14.8 — 2 dp is ~1 km, so GPS jitter reuses one cache entry.
    func testKeyRoundsCoordinatesToTwoDecimals() {
        let a = WeatherLocation(latitude: 51.5074, longitude: -0.1278, name: "A", source: .geo)
        let b = WeatherLocation(latitude: 51.5099, longitude: -0.1299, name: "B", source: .geo)
        XCTAssertEqual(
            DiskCache.key(.forecast, location: a),
            DiskCache.key(.forecast, location: b),
            "51.5074 and 51.5099 both round to 51.51")

        // A genuinely different place must not collide.
        let paris = WeatherLocation(latitude: 48.8534, longitude: 2.3488, name: "Paris", source: .custom)
        XCTAssertNotEqual(
            DiskCache.key(.forecast, location: a), DiskCache.key(.forecast, location: paris))

        // Different kinds never share a file.
        XCTAssertNotEqual(
            DiskCache.key(.forecast, location: a), DiskCache.key(.climatology, location: a))

        XCTAssertEqual(DiskCache.key(.lastLocation, location: nil), "lastLocation")
    }

    /// Just over the 2 dp boundary the two must separate.
    func testKeySeparatesLocationsAcrossTheRoundingBoundary() {
        let a = WeatherLocation(latitude: 51.514, longitude: 0, name: "A", source: .geo)
        let b = WeatherLocation(latitude: 51.516, longitude: 0, name: "B", source: .geo)
        XCTAssertNotEqual(
            DiskCache.key(.forecast, location: a), DiskCache.key(.forecast, location: b))
    }

    // MARK: - TTLs

    func testForecastExpiresAfterFifteenMinutes() async throws {
        let clock = TestClock(Fixture.now)
        let cache = makeCache(clock)
        let forecast = try Fixture.forecast

        await cache.write(forecast, kind: .forecast, location: Fixture.london)

        var hit = await cache.read(ForecastResponse.self, kind: .forecast, location: Fixture.london)
        XCTAssertEqual(hit?.isFresh, true)
        var fresh = await cache.readFresh(
            ForecastResponse.self, kind: .forecast, location: Fixture.london)
        XCTAssertNotNil(fresh)

        clock.advance(by: 16 * 60)
        hit = await cache.read(ForecastResponse.self, kind: .forecast, location: Fixture.london)
        XCTAssertEqual(hit?.isFresh, false, "stale but still servable")
        fresh = await cache.readFresh(
            ForecastResponse.self, kind: .forecast, location: Fixture.london)
        XCTAssertNil(fresh)
    }

    /// §7.1 — stale forecasts stay usable for 3 h when the network is down.
    func testForecastStaleWindowIsThreeHours() async throws {
        let clock = TestClock(Fixture.now)
        let cache = makeCache(clock)
        await cache.write(try Fixture.forecast, kind: .forecast, location: Fixture.london)

        clock.advance(by: 2 * 60 * 60)
        let withinWindow = await cache.read(
            ForecastResponse.self, kind: .forecast, location: Fixture.london)
        XCTAssertNotNil(withinWindow, "within the stale window")

        clock.advance(by: 2 * 60 * 60)  // now 4 h old
        let pastWindow = await cache.read(
            ForecastResponse.self, kind: .forecast, location: Fixture.london)
        XCTAssertNil(pastWindow, "past the stale window")

        // Widgets can still reach it — they must degrade silently (§10.2).
        let hit = await cache.readIgnoringExpiry(
            ForecastResponse.self, kind: .forecast, location: Fixture.london)
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.isFresh, false)
    }

    func testDerivedDataTTLs() async throws {
        let clock = TestClock(Fixture.now)
        let cache = makeCache(clock)
        let ytd = YTDRain(
            labels: ["01-01"], cumCurrentYear: [1], cumHistAvg: [1], cumHistAvgExt: [],
            thisYear: 2026, startYear: 2000, histYears: 4, latestDate: "2026-01-01")

        await cache.write(ytd, kind: .ytdRain, location: Fixture.london)

        clock.advance(by: 23 * 60 * 60)
        let withinTTL = await cache.readFresh(
            YTDRain.self, kind: .ytdRain, location: Fixture.london)
        XCTAssertNotNil(withinTTL)

        clock.advance(by: 2 * 60 * 60)
        let pastTTL = await cache.readFresh(
            YTDRain.self, kind: .ytdRain, location: Fixture.london)
        XCTAssertNil(pastTTL, "24 h TTL")

        // No stale window for derived data — it is simply gone.
        let staleRead = await cache.read(
            YTDRain.self, kind: .ytdRain, location: Fixture.london)
        XCTAssertNil(staleRead)
    }

    func testLastLocationNeverExpires() async {
        let clock = TestClock(Fixture.now)
        let cache = makeCache(clock)
        await cache.write(Fixture.london, kind: .lastLocation)

        clock.advance(by: 365 * 24 * 60 * 60)
        let restored = await cache.readFresh(WeatherLocation.self, kind: .lastLocation)
        XCTAssertEqual(restored, Fixture.london)
    }

    func testRemoveAndRemoveAll() async throws {
        let clock = TestClock(Fixture.now)
        let cache = makeCache(clock)
        await cache.write(try Fixture.forecast, kind: .forecast, location: Fixture.london)
        await cache.write(Fixture.london, kind: .lastLocation)

        await cache.remove(kind: .forecast, location: Fixture.london)
        let removedForecast = await cache.readIgnoringExpiry(
            ForecastResponse.self, kind: .forecast, location: Fixture.london)
        XCTAssertNil(removedForecast)
        let survivingLocation = await cache.readFresh(
            WeatherLocation.self, kind: .lastLocation)
        XCTAssertNotNil(survivingLocation)

        await cache.removeAll()
        let clearedLocation = await cache.readFresh(WeatherLocation.self, kind: .lastLocation)
        XCTAssertNil(clearedLocation)
    }

    func testRoundTripPreservesDerivedValues() async throws {
        let clock = TestClock(Fixture.now)
        let cache = makeCache(clock)
        let climatology = try XCTUnwrap(
            ClimatologyBuilder.build(response: try Fixture.climatology, thisYear: 2026))

        await cache.write(climatology, kind: .climatology, location: Fixture.london)
        let restored = await cache.readFresh(
            Climatology.self, kind: .climatology, location: Fixture.london)
        XCTAssertEqual(restored, climatology)
    }

    // MARK: - Prefs

    private func makePrefs() throws -> (Prefs, UserDefaults, String) {
        let suite = "weatherscope-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (Prefs(defaults: defaults), defaults, suite)
    }

    func testPrefsRoundTripLocationsAndSource() throws {
        let (prefs, defaults, suite) = try makePrefs()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(prefs.activeSource, .geo, "geo by default")
        XCTAssertNil(prefs.customLocation)
        XCTAssertNil(prefs.preferredLocation)

        let paris = WeatherLocation(
            latitude: 48.8534, longitude: 2.3488, name: "Paris, France", source: .custom)
        prefs.customLocation = paris
        prefs.activeSource = .custom
        XCTAssertEqual(prefs.customLocation, paris)
        XCTAssertEqual(prefs.preferredLocation, paris)

        let home = WeatherLocation(
            latitude: 51.5074, longitude: -0.1278, name: "London, England", source: .geo)
        prefs.lastGeoLocation = home
        prefs.activeSource = .geo
        XCTAssertEqual(prefs.preferredLocation, home)

        // A fresh instance over the same suite sees the same values.
        XCTAssertEqual(Prefs(defaults: defaults).customLocation, paris)

        prefs.customLocation = nil
        XCTAssertNil(prefs.customLocation)
        XCTAssertEqual(prefs.preferredLocation, home)
    }

    func testPrefsThemeAndUnits() throws {
        let (prefs, defaults, suite) = try makePrefs()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(prefs.theme, .system)
        prefs.theme = .dark
        XCTAssertEqual(prefs.theme, .dark)
        XCTAssertEqual(Prefs(defaults: defaults).theme, .dark)

        // §1.4.5: the unset default follows the locale.
        XCTAssertEqual(prefs.imperial, Locale.current.measurementSystem == .us)
        prefs.imperial = true
        XCTAssertTrue(prefs.imperial)
        XCTAssertTrue(prefs.formatter.imperial)
        prefs.imperial = false
        XCTAssertFalse(prefs.imperial, "an explicit false must stick, not fall back to the locale")
    }
}
