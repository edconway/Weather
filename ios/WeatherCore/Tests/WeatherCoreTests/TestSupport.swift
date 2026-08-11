import Foundation
import XCTest
@testable import WeatherCore

// MARK: - Fixtures

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json"),
            "missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }

    static var forecast: ForecastResponse { get throws { try decode(ForecastResponse.self, "forecast") } }
    static var climatology: ArchiveResponse { get throws { try decode(ArchiveResponse.self, "climatology") } }
    static var ytd: ArchiveResponse { get throws { try decode(ArchiveResponse.self, "ytd") } }
    static var geocoding: GeocodingResponse { get throws { try decode(GeocodingResponse.self, "geocoding") } }

    static var hourlyNormalWindows: [ArchiveResponse] {
        get throws {
            try (1...5).map { try decode(ArchiveResponse.self, "hourly-normals-y\($0)") }
        }
    }

    /// The instant the fixtures were recorded, in London wall time. Every test
    /// that needs a "now" uses this so expectations stay pinned.
    static let now: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 5
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar.date(from: components)!
    }()

    static let londonTimeZone = TimeZone(identifier: "Europe/London")!
    static let london = WeatherLocation(
        latitude: 51.5074, longitude: -0.1278, name: "London, England", source: .custom)
}

// MARK: - URLProtocol stub

/// Deterministic network stub. `handler` runs on whatever thread URLSession
/// picks, so it must be self-synchronising.
final class MockURLProtocol: URLProtocol {
    struct Stub: @unchecked Sendable {
        var statusCode: Int
        var body: Data
        /// Held open for this long to simulate an in-flight request.
        var delay: Duration
        /// Called the instant the response is handed back, i.e. just before the
        /// throttler releases the request's slot. Lets a test observe the true
        /// in-flight window rather than guessing at it with a second timer.
        var onFinish: (@Sendable () -> Void)?

        init(
            statusCode: Int, body: Data, delay: Duration,
            onFinish: (@Sendable () -> Void)? = nil
        ) {
            self.statusCode = statusCode
            self.body = body
            self.delay = delay
            self.onFinish = onFinish
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handler: (@Sendable (URLRequest) -> Stub)?

    static func setHandler(_ handler: (@Sendable (URLRequest) -> Stub)?) {
        lock.lock(); defer { lock.unlock() }
        _handler = handler
    }

    static var handler: (@Sendable (URLRequest) -> Stub)? {
        lock.lock(); defer { lock.unlock() }
        return _handler
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let stub = handler(request)
        let deliver = { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(
                url: self.request.url!, statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: stub.body)
            stub.onFinish?()
            self.client?.urlProtocolDidFinishLoading(self)
        }
        if stub.delay == .zero {
            deliver()
        } else {
            let seconds = Double(stub.delay.components.seconds)
                + Double(stub.delay.components.attoseconds) / 1e18
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: deliver)
        }
    }

    override func stopLoading() {}
}

/// Thread-safe counter used to assert peak concurrency.
final class ConcurrencyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private(set) var peak = 0
    private(set) var total = 0

    func enter() {
        lock.lock(); defer { lock.unlock() }
        current += 1
        total += 1
        peak = max(peak, current)
    }

    func leave() {
        lock.lock(); defer { lock.unlock() }
        current -= 1
    }
}

/// Records the backoff delays an actor asked for, without actually sleeping.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var durations: [Double] = []

    var sleeper: @Sendable (Duration) async throws -> Void {
        { [self] duration in
            let seconds = Double(duration.components.seconds)
                + Double(duration.components.attoseconds) / 1e18
            lock.lock()
            durations.append(seconds)
            lock.unlock()
        }
    }
}
