import Foundation

/// Absolute temperature colour. The bar is coloured by degrees Celsius, not by
/// where it sits on the track.
public struct TemperatureRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }
}

public enum TemperatureColorScale {
    public static let stops: [(celsius: Double, color: TemperatureRGB)] = [
        (-10, TemperatureRGB(hex: 0x2F8CFF)),
        (0, TemperatureRGB(hex: 0x4FB8FF)),
        (8, TemperatureRGB(hex: 0x9FE6FF)),
        (14, TemperatureRGB(hex: 0xFFE27A)),
        (22, TemperatureRGB(hex: 0xFF9F45)),
        (30, TemperatureRGB(hex: 0xFF5A4E))
    ]

    /// Linear RGB between the fixed stops. Values outside −10…30 clamp to the ends.
    public static func color(celsius: Double) -> TemperatureRGB {
        if celsius <= stops[0].celsius { return stops[0].color }
        if celsius >= stops[stops.count - 1].celsius { return stops[stops.count - 1].color }
        for index in 0..<(stops.count - 1) {
            let left = stops[index]
            let right = stops[index + 1]
            if celsius >= left.celsius, celsius <= right.celsius {
                let span = right.celsius - left.celsius
                let t = span == 0 ? 0 : (celsius - left.celsius) / span
                return TemperatureRGB(
                    red: left.color.red + (right.color.red - left.color.red) * t,
                    green: left.color.green + (right.color.green - left.color.green) * t,
                    blue: left.color.blue + (right.color.blue - left.color.blue) * t)
            }
        }
        return stops[stops.count - 1].color
    }

    /// Colours for a bar that runs from `start` °C to `end` °C.
    /// Location 0 is `start` and location 1 is `end`, wherever that bar sits
    /// on the track. A 3°C bar stays blue. A 30°C bar stays red.
    public static func stops(
        from start: Double, to end: Double
    ) -> [(location: Double, color: TemperatureRGB)] {
        let span = end - start
        if abs(span) < 0.05 {
            let flat = color(celsius: start)
            return [(0, flat), (1, flat)]
        }
        var placed: [(location: Double, color: TemperatureRGB)] = [
            (0, color(celsius: start)),
            (1, color(celsius: end))
        ]
        for stop in self.stops {
            let location = (stop.celsius - start) / span
            if location > 0.02, location < 0.98 {
                placed.append((location, stop.color))
            }
        }
        return placed.sorted { $0.location < $1.location }
    }

    /// Gradient stops across a domain. End colours are the scale at the domain
    /// edges, so a stop that falls outside the domain still tints the end it is
    /// nearest. Interior stops keep their real temperature position.
    public static func gradientStops(
        domain: TemperatureScaleDomain
    ) -> [(location: Double, color: TemperatureRGB)] {
        let span = max(domain.upper - domain.lower, 0.001)
        var stops: [(location: Double, color: TemperatureRGB)] = [
            (0, color(celsius: domain.lower)),
            (1, color(celsius: domain.upper))
        ]
        for stop in self.stops {
            let location = (stop.celsius - domain.lower) / span
            if location > 0.001, location < 0.999 {
                stops.append((location, stop.color))
            }
        }
        return stops.sorted { $0.location < $1.location }
    }
}
