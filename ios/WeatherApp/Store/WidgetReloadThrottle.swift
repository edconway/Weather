import Foundation
import WeatherCore
import WidgetKit

/// Rate-limits `WidgetCenter.reloadAllTimelines()`.
///
/// §10.3 asks the app to reload after every successful fetch, but §14.7 caps
/// reloads at roughly twice an hour. A single app session produces up to four
/// data-changed events (forecast, hourly normals, climatology, refresh), and a
/// user who opens the app a few times an hour would blow the budget outright —
/// after which watchOS simply stops honouring the requests, so the
/// complications get *staler*, not fresher.
///
/// The timestamp lives in the shared defaults so the app and its extensions
/// count against one budget.
enum WidgetReloadThrottle {
    static let minimumInterval: TimeInterval = 30 * 60
    private static let key = "lastWidgetReloadAt"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConfig.appGroup) ?? .standard
    }

    /// Reloads unless one happened recently.
    static func reloadIfDue(now: Date = Date()) {
        let last = defaults.object(forKey: key) as? Date
        if let last, now.timeIntervalSince(last) < minimumInterval { return }
        defaults.set(now, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Bypasses the throttle. Used after a background refresh, which the system
    /// already rate-limits for us.
    static func reloadNow(now: Date = Date()) {
        defaults.set(now, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
