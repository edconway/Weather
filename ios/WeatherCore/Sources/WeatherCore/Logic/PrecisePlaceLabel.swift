import Foundation

/// A short name for the exact point sent to WeatherKit.
///
/// Neighbourhood when reverse geocoding has one that is finer than the city.
/// Otherwise the street, with the building number when it exists. Otherwise the
/// coordinates to four decimal places, about eleven metres.
public enum PrecisePlaceLabel {
    public static func format(
        neighbourhood: String?,
        streetNumber: String?,
        street: String?,
        city: String? = nil,
        latitude: Double,
        longitude: Double
    ) -> String {
        if let neighbourhood = finer(neighbourhood, than: city) {
            return neighbourhood
        }
        if let street = finer(street, than: city) {
            if let number = cleaned(streetNumber), number.caseInsensitiveCompare(street) != .orderedSame {
                return "\(number) \(street)"
            }
            return street
        }
        return coordinates(latitude: latitude, longitude: longitude)
    }

    public static func coordinates(latitude: Double, longitude: Double) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        let latitudeText = String(format: "%.4f", locale: locale, latitude)
        let longitudeText = String(format: "%.4f", locale: locale, longitude)
        return "\(latitudeText), \(longitudeText)"
    }

    private static func finer(_ value: String?, than city: String?) -> String? {
        guard let value = cleaned(value) else { return nil }
        if let city = cleaned(city), value.caseInsensitiveCompare(city) == .orderedSame {
            return nil
        }
        return value
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
