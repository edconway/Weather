import CoreLocation
import Foundation

/// Coordinates → "City, Region".
///
/// PLAN DEVIATION §1.3: CLGeocoder replaces the web app's Nominatim call, so a
/// shipped app does not have to honour OSM's usage policy. Nominatim is kept
/// only as a fallback, rate-limited to one request per second, with the same
/// User-Agent the web app sends.
public actor ReverseGeocoder {
    private let session: URLSession
    private let useNominatimFallback: Bool
    private var lastNominatimRequest: Date?

    public init(session: URLSession = .shared, useNominatimFallback: Bool = true) {
        self.session = session
        self.useNominatimFallback = useNominatimFallback
    }

    /// Never throws — falls back to `"51.51, -0.13"` like the web app's
    /// `geocode()` catch-all, so a naming failure can't block the forecast.
    public func name(latitude: Double, longitude: Double) async -> String {
        if let name = await appleName(latitude: latitude, longitude: longitude) {
            return name
        }
        if useNominatimFallback,
           let name = await nominatimName(latitude: latitude, longitude: longitude) {
            return name
        }
        return Self.coordinateName(latitude: latitude, longitude: longitude)
    }

    static func coordinateName(latitude: Double, longitude: Double) -> String {
        String(format: "%.2f, %.2f", latitude, longitude)
    }

    // MARK: - CLGeocoder

    private func appleName(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first else { return nil }
        return Self.compose(placemark: placemark)
    }

    /// `city, region` with the same field priority as the web app's Nominatim
    /// mapping (`city || town || village || municipality || county`, then
    /// `state || country`).
    static func compose(placemark: CLPlacemark) -> String? {
        let city = placemark.locality
            ?? placemark.subAdministrativeArea
            ?? placemark.name
        guard let city, !city.isEmpty else { return nil }
        let region = placemark.administrativeArea ?? placemark.country
        if let region, !region.isEmpty, region != city {
            return "\(city), \(region)"
        }
        return city
    }

    // MARK: - Nominatim fallback

    private struct NominatimResponse: Decodable {
        struct Address: Decodable {
            let city: String?
            let town: String?
            let village: String?
            let municipality: String?
            let county: String?
            let state: String?
            let country: String?
        }
        let address: Address?
    }

    private func nominatimName(latitude: Double, longitude: Double) async -> String? {
        // §13: one request per second, max.
        if let last = lastNominatimRequest {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < 1 {
                try? await Task.sleep(for: .seconds(1 - elapsed))
            }
        }
        lastNominatimRequest = Date()

        var components = URLComponents()
        components.scheme = "https"
        components.host = "nominatim.openstreetmap.org"
        components.path = "/reverse"
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude))
        ]
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue(AppConfig.userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(NominatimResponse.self, from: data),
              let address = decoded.address
        else { return nil }

        let city = address.city ?? address.town ?? address.village
            ?? address.municipality ?? address.county
        guard let city, !city.isEmpty else { return nil }
        let region = address.state ?? address.country
        if let region, !region.isEmpty { return "\(city), \(region)" }
        return city
    }
}
