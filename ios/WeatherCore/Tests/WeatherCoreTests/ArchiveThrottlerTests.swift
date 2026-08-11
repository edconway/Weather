import XCTest
@testable import WeatherCore

final class ArchiveThrottlerTests: XCTestCase {

    override func tearDown() {
        MockURLProtocol.setHandler(nil)
        super.tearDown()
    }

    private func url(_ index: Int) -> URL {
        URL(string: "https://archive-api.open-meteo.com/v1/archive?n=\(index)")!
    }

    /// §4.4 — never more than three archive requests in flight.
    func testConcurrencyIsCappedAtThree() async throws {
        let probe = ConcurrencyProbe()
        MockURLProtocol.setHandler { _ in
            probe.enter()
            // 50 ms is long enough that concurrent requests genuinely overlap.
            // `onFinish` fires just before the throttler frees the slot, so the
            // probe can only ever under-report — never inflate the peak.
            return .init(
                statusCode: 200, body: Data("{}".utf8), delay: .milliseconds(50),
                onFinish: { probe.leave() })
        }

        let throttler = ArchiveThrottler(session: MockURLProtocol.makeSession())

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    _ = try? await throttler.data(from: self.url(index))
                }
            }
        }

        XCTAssertEqual(probe.total, 12)
        XCTAssertLessThanOrEqual(probe.peak, ArchiveThrottler.maxConcurrent)
        XCTAssertGreaterThan(probe.peak, 1, "requests should actually run in parallel")
    }

    /// §4.4 — 429 retries follow 0.8 / 1.6 / 3.2 / 6.4 s, then give up.
    func testRetryLadderOn429() async throws {
        let attempts = ConcurrencyProbe()
        MockURLProtocol.setHandler { _ in
            attempts.enter()
            attempts.leave()
            return .init(statusCode: 429, body: Data(), delay: .zero)
        }

        let recorder = SleepRecorder()
        let throttler = ArchiveThrottler(
            session: MockURLProtocol.makeSession(), sleeper: recorder.sleeper)

        do {
            _ = try await throttler.data(from: url(0))
            XCTFail("a persistent 429 must surface as an error")
        } catch {
            XCTAssertEqual(error as? WeatherError, .httpStatus(429))
        }

        XCTAssertEqual(recorder.durations, [0.8, 1.6, 3.2, 6.4])
        XCTAssertEqual(attempts.total, 5, "initial attempt + 4 retries")
    }

    func testRecoversWhenARetrySucceeds() async throws {
        let attempts = ConcurrencyProbe()
        MockURLProtocol.setHandler { _ in
            attempts.enter()
            let count = attempts.total
            attempts.leave()
            if count < 3 {
                return .init(statusCode: 429, body: Data(), delay: .zero)
            }
            return .init(statusCode: 200, body: Data(#"{"ok":true}"#.utf8), delay: .zero)
        }

        let recorder = SleepRecorder()
        let throttler = ArchiveThrottler(
            session: MockURLProtocol.makeSession(), sleeper: recorder.sleeper)

        let (data, response) = try await throttler.data(from: url(0))
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"ok":true}"#)
        XCTAssertEqual(recorder.durations, [0.8, 1.6], "two backoffs before the success")
    }

    /// A non-429 error is surfaced immediately — no retries.
    func testServerErrorIsNotRetried() async throws {
        let attempts = ConcurrencyProbe()
        MockURLProtocol.setHandler { _ in
            attempts.enter()
            attempts.leave()
            return .init(statusCode: 500, body: Data(), delay: .zero)
        }

        let recorder = SleepRecorder()
        let throttler = ArchiveThrottler(
            session: MockURLProtocol.makeSession(), sleeper: recorder.sleeper)

        do {
            _ = try await throttler.data(from: url(0))
            XCTFail("expected a 500 to throw")
        } catch {
            XCTAssertEqual(error as? WeatherError, .httpStatus(500))
        }
        XCTAssertEqual(attempts.total, 1)
        XCTAssertTrue(recorder.durations.isEmpty)
    }

    /// A slot must be released even when the transport itself fails, otherwise
    /// one dead request permanently shrinks the pool.
    func testTransportFailureReleasesItsSlot() async throws {
        MockURLProtocol.setHandler(nil)  // makes startLoading fail every request
        let throttler = ArchiveThrottler(session: MockURLProtocol.makeSession())

        for index in 0..<6 {
            do {
                _ = try await throttler.data(from: url(index))
                XCTFail("expected a transport failure")
            } catch {
                XCTAssertFalse(error is WeatherError)
            }
        }

        // Pool is intact: a subsequent success proves slots were returned.
        MockURLProtocol.setHandler { _ in
            .init(statusCode: 200, body: Data("{}".utf8), delay: .zero)
        }
        let (_, response) = try await throttler.data(from: url(99))
        XCTAssertEqual(response.statusCode, 200)
    }
}
