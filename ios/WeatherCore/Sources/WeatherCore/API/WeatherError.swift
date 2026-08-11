import Foundation

public enum WeatherError: Error, Sendable, Equatable, LocalizedError {
    case badResponse
    case httpStatus(Int)
    case decoding(String)
    case locationDenied
    case locationUnavailable
    case locationTimeout
    case noLocation
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .badResponse:
            return "The weather service returned an unexpected response."
        case .httpStatus(let code):
            return "The weather service returned an error (HTTP \(code))."
        case .decoding:
            return "Could not read the weather data."
        case .locationDenied:
            return "Location access denied. Allow location in Settings, or search for a city."
        case .locationUnavailable:
            return "Location unavailable."
        case .locationTimeout:
            return "Location request timed out."
        case .noLocation:
            return "No location set yet."
        case .network(let message):
            return message
        }
    }
}
