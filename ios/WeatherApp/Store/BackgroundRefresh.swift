import BackgroundTasks
import Foundation
import OSLog
import WeatherCore
import WidgetKit

private let log = Logger(subsystem: "com.edconway.weatherworld", category: "background-refresh")

/// iOS background refresh (§7.4).
///
/// Refreshes the active location's forecast into the **shared** cache and then
/// reloads widget timelines, so complications stay current even if the user
/// never opens the app.
///
/// To trigger it manually, pause in the debugger after `schedule()` and run:
///
///     e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.edconway.weatherworld.refresh"]
enum BackgroundRefresh {
    static let identifier = AppConfig.backgroundRefreshTaskID
    /// The system treats this as "no earlier than"; actual cadence is its call.
    static let earliestInterval: TimeInterval = 30 * 60

    /// Must be called before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            log.notice("scheduled background refresh")
        } catch {
            // Common and harmless in the simulator, which has no scheduler.
            log.notice("could not schedule background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Always queue the next one first: if this run is killed, the chain
        // still continues.
        schedule()

        let work = Task {
            let refreshed = await refreshActiveLocation()
            task.setTaskCompleted(success: refreshed)
        }
        task.expirationHandler = {
            work.cancel()
            log.notice("background refresh expired")
        }
    }

    /// Shared by the background task and the foreground "app became active" path.
    @discardableResult
    static func refreshActiveLocation(
        repository: WeatherRepository = WeatherRepository(),
        prefs: Prefs = Prefs()
    ) async -> Bool {
        var target = prefs.preferredLocation
        if target == nil {
            target = await repository.lastLocation()
        }
        guard let location = target else {
            log.notice("no active location to refresh")
            return false
        }
        do {
            _ = try await repository.refreshForecast(for: location)
            // The system already paces background launches, so this one is not
            // throttled further.
            WidgetReloadThrottle.reloadNow()
            log.notice("background refresh updated \(location.name, privacy: .public)")
            return true
        } catch {
            log.error("background refresh failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
