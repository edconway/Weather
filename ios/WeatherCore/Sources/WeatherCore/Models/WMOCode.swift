import Foundation

/// WMO weather-interpretation codes → label and SF Symbol.
///
/// Labels are a 1:1 port of the web app's `WMO` table (`app.js`); the symbol
/// mapping is the plan's §5.2 table (the web app uses emoji).
public enum WMOCode {
    public struct Descriptor: Sendable, Equatable {
        public let label: String
        public let daySymbol: String
        public let nightSymbol: String

        public init(label: String, daySymbol: String, nightSymbol: String) {
            self.label = label
            self.daySymbol = daySymbol
            self.nightSymbol = nightSymbol
        }

        public func symbol(isDay: Bool) -> String { isDay ? daySymbol : nightSymbol }
    }

    static let table: [Int: Descriptor] = [
        0: .init(label: "Clear Sky", daySymbol: "sun.max.fill", nightSymbol: "moon.stars.fill"),
        1: .init(label: "Mainly Clear", daySymbol: "sun.max.fill", nightSymbol: "moon.stars.fill"),
        2: .init(label: "Partly Cloudy", daySymbol: "cloud.sun.fill", nightSymbol: "cloud.moon.fill"),
        3: .init(label: "Overcast", daySymbol: "cloud.fill", nightSymbol: "cloud.fill"),

        45: .init(label: "Foggy", daySymbol: "cloud.fog.fill", nightSymbol: "cloud.fog.fill"),
        48: .init(label: "Icy Fog", daySymbol: "cloud.fog.fill", nightSymbol: "cloud.fog.fill"),

        51: .init(label: "Light Drizzle", daySymbol: "cloud.drizzle.fill", nightSymbol: "cloud.drizzle.fill"),
        53: .init(label: "Drizzle", daySymbol: "cloud.drizzle.fill", nightSymbol: "cloud.drizzle.fill"),
        55: .init(label: "Heavy Drizzle", daySymbol: "cloud.drizzle.fill", nightSymbol: "cloud.drizzle.fill"),

        56: .init(label: "Light Freezing Drizzle", daySymbol: "cloud.sleet.fill", nightSymbol: "cloud.sleet.fill"),
        57: .init(label: "Freezing Drizzle", daySymbol: "cloud.sleet.fill", nightSymbol: "cloud.sleet.fill"),

        61: .init(label: "Light Rain", daySymbol: "cloud.rain.fill", nightSymbol: "cloud.rain.fill"),
        63: .init(label: "Rain", daySymbol: "cloud.rain.fill", nightSymbol: "cloud.rain.fill"),
        65: .init(label: "Heavy Rain", daySymbol: "cloud.heavyrain.fill", nightSymbol: "cloud.heavyrain.fill"),

        66: .init(label: "Light Freezing Rain", daySymbol: "cloud.sleet.fill", nightSymbol: "cloud.sleet.fill"),
        67: .init(label: "Freezing Rain", daySymbol: "cloud.sleet.fill", nightSymbol: "cloud.sleet.fill"),

        71: .init(label: "Light Snow", daySymbol: "cloud.snow.fill", nightSymbol: "cloud.snow.fill"),
        73: .init(label: "Snow", daySymbol: "cloud.snow.fill", nightSymbol: "cloud.snow.fill"),
        75: .init(label: "Heavy Snow", daySymbol: "cloud.snow.fill", nightSymbol: "cloud.snow.fill"),
        77: .init(label: "Snow Grains", daySymbol: "cloud.snow.fill", nightSymbol: "cloud.snow.fill"),

        80: .init(label: "Light Showers", daySymbol: "cloud.sun.rain.fill", nightSymbol: "cloud.moon.rain.fill"),
        81: .init(label: "Showers", daySymbol: "cloud.rain.fill", nightSymbol: "cloud.rain.fill"),
        82: .init(label: "Heavy Showers", daySymbol: "cloud.heavyrain.fill", nightSymbol: "cloud.heavyrain.fill"),

        85: .init(label: "Snow Showers", daySymbol: "cloud.snow.fill", nightSymbol: "cloud.snow.fill"),
        86: .init(label: "Heavy Snow Showers", daySymbol: "cloud.snow.fill", nightSymbol: "cloud.snow.fill"),

        95: .init(label: "Thunderstorm", daySymbol: "cloud.bolt.fill", nightSymbol: "cloud.bolt.fill"),
        96: .init(label: "Thunderstorm & Hail", daySymbol: "cloud.bolt.rain.fill", nightSymbol: "cloud.bolt.rain.fill"),
        99: .init(label: "Thunderstorm & Heavy Hail", daySymbol: "cloud.bolt.rain.fill", nightSymbol: "cloud.bolt.rain.fill")
    ]

    static let unknown = Descriptor(
        label: "Unknown", daySymbol: "thermometer.medium", nightSymbol: "thermometer.medium")

    /// Port of `wmo(c)`: exact match, else the code rounded down to the nearest
    /// ten, else "Unknown".
    public static func describe(_ code: Int?) -> Descriptor {
        guard let code else { return unknown }
        if let exact = table[code] { return exact }
        if let decade = table[(code / 10) * 10] { return decade }
        return unknown
    }
}
