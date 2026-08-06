import Foundation
import OSLog
import WeatherCore
import WidgetKit
import WatchKit

private let log = Logger(subsystem: "com.edconway.weatherworld", category: "background-refresh")

/// watchOS background refresh (§7.4).
///
/// Deliberately independent of `WatchStore`: the background task runs with no
/// UI, and reaching into a main-actor observable object from a `Scene`-level
/// closure is both awkward and unnecessary. This works straight off the shared
/// cache, exactly as the timeline provider does.
enum WatchBackgroundRefresh {
    static let interval: TimeInterval = 30 * 60

    static func schedule() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: interval),
            userInfo: nil
        ) { error in
            if let error {
                log.notice("could not schedule watch refresh: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Refreshes the cached forecast, reloads complications, and queues the
    /// next run. Never throws — a failed refresh must not break the chain.
    static func run() async {
        defer { schedule() }

        let cache = DiskCache()
        guard let location = await cache.readFresh(
            WeatherLocation.self, kind: .lastLocation) else {
            log.notice("watch refresh: no cached location")
            return
        }
        do {
            let forecast = try await OpenMeteoClient().forecast(
                latitude: location.latitude, longitude: location.longitude)
            await cache.write(forecast, kind: .forecast, location: location)
            WidgetCenter.shared.reloadAllTimelines()
            log.notice("watch refresh updated \(location.name, privacy: .public)")
        } catch {
            log.error("watch refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
