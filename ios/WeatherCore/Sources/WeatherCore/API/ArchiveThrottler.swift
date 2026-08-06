import Foundation

/// Serialises archive requests: **max 3 concurrent**, FIFO queue for the rest,
/// and a 429 retry ladder of 0.8 / 1.6 / 3.2 / 6.4 s (`0.4 * 2^tries`).
///
/// A 1:1 port of `archiveFetch` / `_drainArchive` in `app.js`. Only the archive
/// host rate-limits in practice; forecast and geocoding go direct (§4.4).
public actor ArchiveThrottler {
    public static let maxConcurrent = 3
    public static let maxRetries = 4

    private let session: URLSession
    /// Scales every backoff delay. Tests set this to a small value to keep the
    /// retry ladder's *shape* while running in milliseconds.
    private let backoffScale: Double
    private let sleeper: @Sendable (Duration) async throws -> Void

    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(
        session: URLSession = .shared,
        backoffScale: Double = 1.0,
        sleeper: (@Sendable (Duration) async throws -> Void)? = nil
    ) {
        self.session = session
        self.backoffScale = backoffScale
        self.sleeper = sleeper ?? { try await Task.sleep(for: $0) }
    }

    /// Fetches `url`, waiting for a concurrency slot first and retrying on 429.
    public func data(from url: URL) async throws -> (Data, HTTPURLResponse) {
        var tries = 0
        while true {
            await acquire(front: tries > 0)
            let result: (Data, HTTPURLResponse)
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw WeatherError.badResponse
                }
                result = (data, http)
            } catch {
                release()
                throw error
            }
            release()

            if result.1.statusCode == 429 && tries < Self.maxRetries {
                tries += 1
                // 0.4 * 2^tries seconds → 0.8, 1.6, 3.2, 6.4.
                let seconds = 0.4 * pow(2.0, Double(tries)) * backoffScale
                try await sleeper(.seconds(seconds))
                // Retries jump the queue, matching the web's `unshift`.
                continue
            }

            guard (200..<300).contains(result.1.statusCode) else {
                throw WeatherError.httpStatus(result.1.statusCode)
            }
            return result
        }
    }

    /// Decodes an archive response through the throttler.
    public func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, _) = try await data(from: url)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WeatherError.decoding(String(describing: error))
        }
    }

    // MARK: - Concurrency gate

    private func acquire(front: Bool) async {
        if active < Self.maxConcurrent {
            active += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if front {
                waiters.insert(continuation, at: 0)
            } else {
                waiters.append(continuation)
            }
        }
        active += 1
    }

    private func release() {
        active -= 1
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}
