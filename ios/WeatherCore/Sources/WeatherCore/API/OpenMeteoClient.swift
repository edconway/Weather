import Foundation

/// Forecast and geocoding endpoints. Neither is rate-limited in practice, so
/// both go direct rather than through `ArchiveThrottler` (§4.4).
public struct OpenMeteoClient: Sendable {
    public static let forecastHost = "api.open-meteo.com"
    public static let geocodingHost = "geocoding-api.open-meteo.com"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Forecast (§4.1)

    static let dailyVariables = [
        "weather_code",
        "temperature_2m_max",
        "temperature_2m_min",
        "wet_bulb_temperature_2m_max",
        "wet_bulb_temperature_2m_min",
        "apparent_temperature_max",
        "precipitation_sum",
        "precipitation_probability_max",
        "wind_speed_10m_max",
        "uv_index_max",
        // Not in the web app: drives the corner complication's next sun event.
        "sunrise",
        "sunset"
    ]

    static let hourlyVariables = [
        "temperature_2m",
        "wet_bulb_temperature_2m",
        "apparent_temperature",
        "precipitation",
        "precipitation_probability",
        "rain",
        "showers",
        "snowfall",
        "weather_code",
        // PLAN DEVIATION §1.4.1: not requested by the web app.
        "is_day"
    ]

    public static func forecastURL(latitude: Double, longitude: Double) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = forecastHost
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "past_days", value: "7"),
            URLQueryItem(name: "daily", value: dailyVariables.joined(separator: ",")),
            URLQueryItem(name: "past_hours", value: "24"),
            URLQueryItem(name: "forecast_hours", value: "48"),
            URLQueryItem(name: "hourly", value: hourlyVariables.joined(separator: ","))
        ]
        return components.url!
    }

    public func forecast(latitude: Double, longitude: Double) async throws -> ForecastResponse {
        try await get(ForecastResponse.self, from: Self.forecastURL(latitude: latitude, longitude: longitude))
    }

    // MARK: - Geocoding search (§4.3)

    public static func searchURL(query: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = geocodingHost
        components.path = "/v1/search"
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        return components.url!
    }

    public func search(query: String) async throws -> [GeocodingResponse.Result] {
        let response = try await get(GeocodingResponse.self, from: Self.searchURL(query: query))
        return response.results ?? []
    }

    // MARK: -

    private func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw WeatherError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw WeatherError.httpStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WeatherError.decoding(String(describing: error))
        }
    }
}
