import Foundation

/// Decoded `https://geocoding-api.open-meteo.com/v1/search` response.
public struct GeocodingResponse: Codable, Sendable, Equatable {
    public let results: [Result]?

    public init(results: [Result]?) { self.results = results }

    public struct Result: Codable, Sendable, Equatable, Identifiable {
        public let id: Int
        public let name: String
        public let latitude: Double
        public let longitude: Double
        public let admin1: String?
        public let country: String?
        public let countryCode: String?

        public init(
            id: Int,
            name: String,
            latitude: Double,
            longitude: Double,
            admin1: String? = nil,
            country: String? = nil,
            countryCode: String? = nil
        ) {
            self.id = id
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.admin1 = admin1
            self.country = country
            self.countryCode = countryCode
        }

        enum CodingKeys: String, CodingKey {
            case id, name, latitude, longitude, admin1, country
            case countryCode = "country_code"
        }

        /// Full display name, identical to the web app's `pickResult` label:
        /// `name[, admin1][, country]`.
        public var displayName: String {
            [name, admin1, country].compactMap { $0 }.joined(separator: ", ")
        }

        /// Secondary line in the search list: `admin1, CC`.
        public var detail: String {
            [admin1, countryCode].compactMap { $0 }.joined(separator: ", ")
        }
    }
}
