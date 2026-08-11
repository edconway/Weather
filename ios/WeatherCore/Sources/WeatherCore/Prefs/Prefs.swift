import Foundation

/// The web app's `localStorage` preferences, on `UserDefaults(suiteName:)` so
/// widgets read the same values (§7.3).
/// `UserDefaults` is thread-safe but not formally `Sendable`, hence the
/// `@unchecked` conformance.
public struct Prefs: @unchecked Sendable {
    public enum ThemeOverride: String, Sendable, CaseIterable, Identifiable {
        case system, light, dark
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    enum Key {
        static let imperial = "imperial"
        static let theme = "theme"
        static let activeSource = "activeSource"
        static let customLat = "customLat"
        static let customLon = "customLon"
        static let customName = "customName"
        static let lastGeoLat = "lastGeoLat"
        static let lastGeoLon = "lastGeoLon"
        static let lastGeoName = "lastGeoName"
    }

    private let defaults: UserDefaults

    public init(suiteName: String = AppConfig.appGroup) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    // MARK: - Units

    /// PLAN DEVIATION §1.4.5: defaults from the locale rather than always metric.
    public var imperial: Bool {
        get {
            defaults.object(forKey: Key.imperial) as? Bool
                ?? (Locale.current.measurementSystem == .us)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.imperial) }
    }

    public var formatter: UnitFormatter { UnitFormatter(imperial: imperial) }

    // MARK: - Theme

    public var theme: ThemeOverride {
        get {
            (defaults.string(forKey: Key.theme).flatMap(ThemeOverride.init(rawValue:))) ?? .system
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.theme) }
    }

    // MARK: - Locations

    public var activeSource: WeatherLocation.Source {
        get {
            (defaults.string(forKey: Key.activeSource)
                .flatMap(WeatherLocation.Source.init(rawValue:))) ?? .geo
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.activeSource) }
    }

    public var customLocation: WeatherLocation? {
        get { location(latKey: Key.customLat, lonKey: Key.customLon, nameKey: Key.customName, source: .custom) }
        nonmutating set {
            store(newValue, latKey: Key.customLat, lonKey: Key.customLon, nameKey: Key.customName)
        }
    }

    public var lastGeoLocation: WeatherLocation? {
        get { location(latKey: Key.lastGeoLat, lonKey: Key.lastGeoLon, nameKey: Key.lastGeoName, source: .geo) }
        nonmutating set {
            store(newValue, latKey: Key.lastGeoLat, lonKey: Key.lastGeoLon, nameKey: Key.lastGeoName)
        }
    }

    /// The location the app should open with, honouring `activeSource` and
    /// falling back to whichever one exists (boot flow §8.1).
    public var preferredLocation: WeatherLocation? {
        switch activeSource {
        case .custom: return customLocation ?? lastGeoLocation
        case .geo: return lastGeoLocation ?? customLocation
        }
    }

    public func location(for source: WeatherLocation.Source) -> WeatherLocation? {
        source == .custom ? customLocation : lastGeoLocation
    }

    private func location(
        latKey: String, lonKey: String, nameKey: String, source: WeatherLocation.Source
    ) -> WeatherLocation? {
        guard defaults.object(forKey: latKey) != nil,
              defaults.object(forKey: lonKey) != nil else { return nil }
        return WeatherLocation(
            latitude: defaults.double(forKey: latKey),
            longitude: defaults.double(forKey: lonKey),
            name: defaults.string(forKey: nameKey) ?? "",
            source: source)
    }

    private func store(
        _ location: WeatherLocation?, latKey: String, lonKey: String, nameKey: String
    ) {
        guard let location else {
            defaults.removeObject(forKey: latKey)
            defaults.removeObject(forKey: lonKey)
            defaults.removeObject(forKey: nameKey)
            return
        }
        defaults.set(location.latitude, forKey: latKey)
        defaults.set(location.longitude, forKey: lonKey)
        defaults.set(location.name, forKey: nameKey)
    }

    /// Everything the watch needs to mirror the phone's display choices.
    public func syncedFromPhone(imperial: Bool) {
        defaults.set(imperial, forKey: Key.imperial)
    }
}
