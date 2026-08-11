import Foundation

/// Identifiers shared by every target. Change these in one place if the app is renamed.
public enum AppConfig {
    public static let appGroup = "group.com.edconway.weatherworld"
    public static let backgroundRefreshTaskID = "com.edconway.weatherworld.refresh"
    public static let deepLinkScheme = "weatherworld"
    public static let todayDeepLink = URL(string: "weatherworld://today")!

    /// Sent with the Nominatim reverse-geocoding fallback, matching the web app's UA.
    public static let userAgent = "WeatherApp/1.0 (https://github.com/edconway/Weather)"

    /// Deep link that scrolls the Today screen to a specific panel — used by
    /// widgets whose content maps onto one panel (rain, temperature anomaly).
    public static func panelDeepLink(_ panel: PanelID) -> URL {
        URL(string: "\(deepLinkScheme)://panel/\(panel.rawValue)")!
    }

    /// Inverse of `panelDeepLink`. Returns `nil` for the plain today link or
    /// any URL that isn't one of ours.
    public static func panel(from url: URL) -> PanelID? {
        guard url.scheme == deepLinkScheme, url.host == "panel" else { return nil }
        return PanelID(rawValue: url.lastPathComponent)
    }
}
