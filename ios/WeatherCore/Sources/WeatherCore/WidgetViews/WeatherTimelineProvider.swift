#if canImport(WidgetKit)
import Foundation
import WidgetKit

public struct WeatherTimelineEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WeatherEntrySnapshot

    public init(date: Date, snapshot: WeatherEntrySnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

/// §10.2 — one provider shared by every widget on both platforms.
///
/// Reads the App Group cache, refetches the **forecast only** when it is older
/// than 45 minutes, and never touches the archive API (§10.3, §14.7). Lives in
/// `WeatherCore` so the watchOS and iOS extensions cannot drift apart.
public struct WeatherTimelineProvider: TimelineProvider {
    public static let staleAfter: TimeInterval = 45 * 60
    public static let reloadInterval: TimeInterval = 30 * 60
    public static let emptyReloadInterval: TimeInterval = 60 * 60
    public static let fetchTimeout: TimeInterval = 10

    public init() {}

    public func placeholder(in context: Context) -> WeatherTimelineEntry {
        WeatherTimelineEntry(date: Date(), snapshot: .placeholder)
    }

    public func getSnapshot(
        in context: Context, completion: @escaping (WeatherTimelineEntry) -> Void
    ) {
        // The gallery must never show an empty dial, so preview with plausible
        // static data rather than whatever happens to be cached.
        if context.isPreview {
            completion(WeatherTimelineEntry(date: Date(), snapshot: .placeholder))
            return
        }
        Task {
            let entries = await Self.buildEntries(now: Date())
            completion(entries.first ?? WeatherTimelineEntry(date: Date(), snapshot: .placeholder))
        }
    }

    public func getTimeline(
        in context: Context, completion: @escaping (Timeline<WeatherTimelineEntry>) -> Void
    ) {
        Task {
            let now = Date()
            let entries = await Self.buildEntries(now: now)
            guard !entries.isEmpty else {
                completion(Timeline(
                    entries: [WeatherTimelineEntry(date: now, snapshot: .empty(date: now))],
                    policy: .after(now.addingTimeInterval(Self.emptyReloadInterval))))
                return
            }
            completion(Timeline(
                entries: entries,
                policy: .after(now.addingTimeInterval(Self.reloadInterval))))
        }
    }

    // MARK: -

    static func buildEntries(now: Date) async -> [WeatherTimelineEntry] {
        let cache = DiskCache()
        guard let location = await cache.readFresh(
            WeatherLocation.self, kind: .lastLocation) else { return [] }

        let prefs = Prefs()
        let payload = await cache.readFresh(WatchSyncPayload.self, kind: .watchPayload)

        var forecast: ForecastResponse?
        let cached = await cache.readIgnoringExpiry(
            ForecastResponse.self, kind: .forecast, location: location)

        let age = cached.map { now.timeIntervalSince($0.savedAt) } ?? .infinity
        if age > staleAfter {
            forecast = await fetchForecast(for: location)
            if let forecast {
                await cache.write(forecast, kind: .forecast, location: location)
            }
        }
        // On a failed fetch the stale copy is used silently — a complication
        // showing slightly old weather beats one showing nothing (§10.2).
        if forecast == nil { forecast = cached?.value }
        guard let forecast else { return [] }

        return WidgetSnapshotBuilder.entries(
            forecast: forecast,
            location: location,
            payload: payload,
            imperial: prefs.imperial,
            now: now
        ).map { WeatherTimelineEntry(date: $0.date, snapshot: $0) }
    }

    private static func fetchForecast(for location: WeatherLocation) async -> ForecastResponse? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = fetchTimeout
        configuration.waitsForConnectivity = false
        let client = OpenMeteoClient(session: URLSession(configuration: configuration))
        return try? await client.forecast(
            latitude: location.latitude, longitude: location.longitude)
    }
}
#endif
