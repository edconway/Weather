import Foundation

/// A place the app can show weather for.
public struct WeatherLocation: Codable, Sendable, Equatable, Hashable {
    public enum Source: String, Codable, Sendable {
        /// Device GPS fix.
        case geo
        /// Picked from search.
        case custom
    }

    public let latitude: Double
    public let longitude: Double
    public let name: String
    public let source: Source

    public init(latitude: Double, longitude: Double, name: String, source: Source) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.source = source
    }

    /// City-only name, i.e. everything before the first comma — the web app's
    /// `geoName.split(',')[0].trim()`.
    ///
    /// When reverse geocoding fails the name is a `"51.51, -0.13"` coordinate
    /// pair, and splitting that on the comma yields a bare, meaningless "51.51".
    /// Coordinate names are therefore kept whole.
    public var shortName: String {
        guard let first = name.split(separator: ",").first else { return name }
        let head = first.trimmingCharacters(in: .whitespaces)
        return Double(head) == nil ? head : name
    }

    /// Cache/identity key, rounded to 2 decimals (~1 km) so GPS jitter does not
    /// bust the cache (§7.1, §14.8).
    public var cacheKey: String {
        String(format: "%.2f-%.2f", latitude, longitude)
    }

    /// Great-circle distance in metres, used for the watch's 25 km normals guard (§9.2).
    public func distance(to other: WeatherLocation) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }
}
