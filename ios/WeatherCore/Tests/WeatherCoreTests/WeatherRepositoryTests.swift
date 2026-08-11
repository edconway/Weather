import XCTest
@testable import WeatherCore

/// §7.1/§7.4 — the derived-data caches (climatology, hourly normals) key their
/// TTL on wall-clock time alone, but their *content* is also implicitly scoped
/// to "the year before now". A blob built in December is still within its TTL
/// in January, yet describes the wrong decade. These tests pin the fix: a
/// cached entry is only honoured when its year window still ends last year.
final class WeatherRepositoryTests: XCTestCase {

    /// Advanceable clock, private to this file (`CacheAndPrefsTests.TestClock`
    /// is a nested type there and not worth coupling to).
    final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var now: Date
        init(_ start: Date) { now = start }
        var date: Date {
            lock.lock(); defer { lock.unlock() }
            return now
        }
        func set(_ date: Date) {
            lock.lock(); defer { lock.unlock() }
            now = date
        }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("weatherscope-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func newYearInstant(_ year: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(
            year: year, month: 1, day: 3, hour: 9))!
    }

    private func makeRepository(
        clock: TestClock, handler: @escaping @Sendable (URLRequest) -> MockURLProtocol.Stub
    ) -> WeatherRepository {
        MockURLProtocol.setHandler(handler)
        let throttler = ArchiveThrottler(session: MockURLProtocol.makeSession())
        let archiveClient = ArchiveClient(throttler: throttler)
        let cache = DiskCache(directory: directory, clock: { clock.date })
        return WeatherRepository(archiveClient: archiveClient, cache: cache, clock: { clock.date })
    }

    // MARK: - Climatology

    /// A climatology cached with last year's window is honoured as-is: no
    /// network call, and the returned value is the cached one.
    func testClimatologyCacheHitWhenYearWindowIsCurrent() async throws {
        let clock = TestClock(newYearInstant(2026))
        let networkCalls = ConcurrencyProbe()
        let repository = makeRepository(clock: clock) { _ in
            networkCalls.enter()
            networkCalls.leave()
            return .init(statusCode: 500, body: Data(), delay: .zero)  // must not be reached
        }

        let stale2025Window = Climatology(
            months: (0..<12).map { _ in MonthNormal(tMax: 10, tMin: 5, rain: 20) },
            byMMDD: [:], yearStart: 2016, yearEnd: 2025)
        await repository.diskCache.write(
            stale2025Window, kind: .climatology, location: Fixture.london)

        let result = try await repository.climatology(
            for: Fixture.london, now: clock.date, timeZone: Fixture.londonTimeZone)

        XCTAssertEqual(result, stale2025Window)
        XCTAssertEqual(networkCalls.total, 0, "a same-year cache hit must not fetch")
    }

    /// A climatology cached for the *previous* year window is rejected even
    /// though it is well within its 30-day TTL — the exact bug this guards.
    func testClimatologyCacheMissAcrossTheYearBoundary() async throws {
        let clock = TestClock(newYearInstant(2026))
        let fixtureBody = try Fixture.data("climatology")
        let repository = makeRepository(clock: clock) { _ in
            .init(statusCode: 200, body: fixtureBody, delay: .zero)
        }

        // Built 5 days ago (December 29, well inside the 30-day TTL) describing
        // 2015...2024 — the correct window as of *that* call, now one year stale.
        let staleClock = TestClock(newYearInstant(2026).addingTimeInterval(-5 * 86400))
        let stale2024Window = Climatology(
            months: (0..<12).map { _ in MonthNormal(tMax: 1, tMin: -1, rain: 1) },
            byMMDD: [:], yearStart: 2015, yearEnd: 2024)
        let seedCache = DiskCache(directory: directory, clock: { staleClock.date })
        await seedCache.write(stale2024Window, kind: .climatology, location: Fixture.london)

        let result = try await repository.climatology(
            for: Fixture.london, now: clock.date, timeZone: Fixture.londonTimeZone)

        XCTAssertNotEqual(result, stale2024Window, "the year-stale cache entry must be rejected")
        XCTAssertEqual(result.yearEnd, 2025, "freshly built window must end last year")

        // The freshly-fetched result must now be what a second call returns,
        // this time from cache with no further fetch.
        let networkCalls = ConcurrencyProbe()
        let repository2 = makeRepository(clock: clock) { _ in
            networkCalls.enter()
            networkCalls.leave()
            return .init(statusCode: 500, body: Data(), delay: .zero)
        }
        let cached = try await repository2.climatology(
            for: Fixture.london, now: clock.date, timeZone: Fixture.londonTimeZone)
        XCTAssertEqual(cached.yearEnd, 2025)
        XCTAssertEqual(networkCalls.total, 0)
    }

    // MARK: - Hourly normals

    func testHourlyNormalsCacheMissAcrossTheYearBoundary() async throws {
        let clock = TestClock(newYearInstant(2026))
        let windowBody = try Fixture.data("hourly-normals-y1")
        let repository = makeRepository(clock: clock) { _ in
            .init(statusCode: 200, body: windowBody, delay: .zero)
        }

        let staleNormals = HourlyNormals(
            temp: HourAverages(avgByHour: [Double?](repeating: 10, count: 24), yearStart: 2020, yearEnd: 2024),
            wetBulb: HourAverages(avgByHour: [Double?](repeating: 8, count: 24), yearStart: 2020, yearEnd: 2024),
            rain: RainHourNormals(
                avgByHour: [Double](repeating: 0, count: 24),
                wetHourProbabilityByHour: [Double](repeating: 0, count: 24),
                p90ByHour: [Double](repeating: 0, count: 24),
                yearStart: 2020, yearEnd: 2024))
        await repository.diskCache.write(
            staleNormals, kind: .hourlyNormals, location: Fixture.london)

        let result = try await repository.hourlyNormals(
            for: Fixture.london, now: clock.date, timeZone: Fixture.londonTimeZone)

        XCTAssertNotEqual(result.temp.yearEnd, 2024, "the year-stale cache entry must be rejected")
        XCTAssertEqual(result.temp.yearEnd, 2025)
    }

    func testHourlyNormalsCacheHitWhenYearWindowIsCurrent() async throws {
        let clock = TestClock(newYearInstant(2026))
        let networkCalls = ConcurrencyProbe()
        let repository = makeRepository(clock: clock) { _ in
            networkCalls.enter()
            networkCalls.leave()
            return .init(statusCode: 500, body: Data(), delay: .zero)
        }

        let currentNormals = HourlyNormals(
            temp: HourAverages(avgByHour: [Double?](repeating: 12, count: 24), yearStart: 2021, yearEnd: 2025),
            wetBulb: HourAverages(avgByHour: [Double?](repeating: 9, count: 24), yearStart: 2021, yearEnd: 2025),
            rain: RainHourNormals(
                avgByHour: [Double](repeating: 0.1, count: 24),
                wetHourProbabilityByHour: [Double](repeating: 0.2, count: 24),
                p90ByHour: [Double](repeating: 1, count: 24),
                yearStart: 2021, yearEnd: 2025))
        await repository.diskCache.write(
            currentNormals, kind: .hourlyNormals, location: Fixture.london)

        let result = try await repository.hourlyNormals(
            for: Fixture.london, now: clock.date, timeZone: Fixture.londonTimeZone)

        XCTAssertEqual(result, currentNormals)
        XCTAssertEqual(networkCalls.total, 0, "a same-year cache hit must not fetch")
    }
}
