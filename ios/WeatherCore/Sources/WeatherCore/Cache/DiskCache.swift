import Foundation

/// JSON file cache in the App Group container, shared between an app and **its
/// own** widget extension on the same device.
///
/// App Groups do not span iPhone ↔ Watch — that is what WatchConnectivity is
/// for (§14.6).
public actor DiskCache {
    /// What is cached, and for how long (§7.1).
    public enum Kind: String, Sendable, CaseIterable {
        case forecast
        case hourlyNormals
        case climatology
        case ytdRain
        case lastLocation
        case watchPayload

        public var timeToLive: TimeInterval? {
            switch self {
            case .forecast: return 15 * 60
            case .hourlyNormals: return 7 * 24 * 60 * 60
            case .climatology: return 30 * 24 * 60 * 60
            case .ytdRain: return 24 * 60 * 60
            case .lastLocation, .watchPayload: return nil  // never expires
            }
        }

        /// How long a stale entry may still be served when the network fails
        /// (§7.1, forecast only).
        public var staleWhileRevalidate: TimeInterval? {
            self == .forecast ? 3 * 60 * 60 : nil
        }
    }

    public struct Entry<Value: Codable & Sendable>: Codable, Sendable {
        public let savedAt: Date
        public let value: Value
    }

    /// A cache read, with enough context for the caller to decide whether stale
    /// data is good enough.
    public struct Hit<Value: Sendable>: Sendable {
        public let value: Value
        public let savedAt: Date
        public let isFresh: Bool
    }

    private let directory: URL
    private let clock: @Sendable () -> Date
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Falls back to the app's own caches directory when the App Group container
    /// is unavailable (which happens in unit tests and unsigned builds).
    public init(
        appGroup: String = AppConfig.appGroup,
        directory: URL? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        let base = directory
            ?? FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
                .appendingPathComponent("Caches", isDirectory: true)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("WeatherWorld", isDirectory: true)
        self.directory = base
        self.clock = clock
        try? FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true)
    }

    /// `{kind}-{lat}-{lon}` with coordinates at 2 dp (§7.1).
    nonisolated public static func key(_ kind: Kind, location: WeatherLocation?) -> String {
        guard let location else { return kind.rawValue }
        return "\(kind.rawValue)-\(location.cacheKey)"
    }

    private func url(for key: String) -> URL {
        // Keys contain '-' and '.' only, but be defensive about path traversal.
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    // MARK: - Reads

    /// Returns a hit whenever the file exists, flagging whether it is still
    /// fresh. Entries past their stale-while-revalidate window are dropped.
    public func read<Value: Codable & Sendable>(
        _ type: Value.Type, kind: Kind, location: WeatherLocation? = nil
    ) -> Hit<Value>? {
        let key = Self.key(kind, location: location)
        guard let data = try? Data(contentsOf: url(for: key)),
              let entry = try? decoder.decode(Entry<Value>.self, from: data)
        else { return nil }

        let age = clock().timeIntervalSince(entry.savedAt)
        guard let ttl = kind.timeToLive else {
            return Hit(value: entry.value, savedAt: entry.savedAt, isFresh: true)
        }
        if age <= ttl {
            return Hit(value: entry.value, savedAt: entry.savedAt, isFresh: true)
        }
        if let window = kind.staleWhileRevalidate, age <= window {
            return Hit(value: entry.value, savedAt: entry.savedAt, isFresh: false)
        }
        // Beyond every window: treat as absent, but leave the file for the
        // caller's own last-ditch `readIgnoringExpiry`.
        return nil
    }

    /// Fresh values only.
    public func readFresh<Value: Codable & Sendable>(
        _ type: Value.Type, kind: Kind, location: WeatherLocation? = nil
    ) -> Value? {
        let hit = read(type, kind: kind, location: location)
        return hit?.isFresh == true ? hit?.value : nil
    }

    /// Any value, however old — used by widgets, which must degrade silently
    /// rather than show nothing (§10.2).
    public func readIgnoringExpiry<Value: Codable & Sendable>(
        _ type: Value.Type, kind: Kind, location: WeatherLocation? = nil
    ) -> Hit<Value>? {
        let key = Self.key(kind, location: location)
        guard let data = try? Data(contentsOf: url(for: key)),
              let entry = try? decoder.decode(Entry<Value>.self, from: data)
        else { return nil }
        let age = clock().timeIntervalSince(entry.savedAt)
        let fresh = kind.timeToLive.map { age <= $0 } ?? true
        return Hit(value: entry.value, savedAt: entry.savedAt, isFresh: fresh)
    }

    // MARK: - Writes

    public func write<Value: Codable & Sendable>(
        _ value: Value, kind: Kind, location: WeatherLocation? = nil
    ) {
        let entry = Entry(savedAt: clock(), value: value)
        guard let data = try? encoder.encode(entry) else { return }
        try? data.write(to: url(for: Self.key(kind, location: location)), options: .atomic)
    }

    public func remove(kind: Kind, location: WeatherLocation? = nil) {
        try? FileManager.default.removeItem(at: url(for: Self.key(kind, location: location)))
    }

    public func removeAll() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
