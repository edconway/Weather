import Foundation

/// Identifiers shared by every target. Change these in one place if the app is renamed.
public enum AppConfig {
    public static let appGroup = "group.com.edconway.weatherworld"
    public static let backgroundRefreshTaskID = "com.edconway.weatherworld.refresh"
    public static let deepLinkScheme = "weatherworld"
    public static let todayDeepLink = URL(string: "weatherworld://today")!

    /// Sent with the Nominatim reverse-geocoding fallback, matching the web app's UA.
    public static let userAgent = "WeatherApp/1.0 (https://github.com/edconway/Weather)"
}
