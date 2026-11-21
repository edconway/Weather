import SwiftUI
import WeatherCore

/// Semantic series colors and condition-driven atmosphere. Panel-cap chrome
/// hexes are retired — sections no longer tint their headers.
enum Palette {
    static let accent = Color.accentColor

    /// Chart series — slightly desaturated so they sit on sky/background.
    static let hot = Color(red: 0.82, green: 0.36, blue: 0.30)
    static let cold = Color(red: 0.30, green: 0.52, blue: 0.78)
    static let rainSeries = Color(red: 0.32, green: 0.48, blue: 0.82)
    static let wetBulb = Color(red: 0.28, green: 0.58, blue: 0.55)
    static let historical = Color.secondary

    /// Legacy aliases used by a few chrome call sites.
    static let temperature = hot
    static let rain = rainSeries

    static func badgeForeground(_ kind: AnomalyKind) -> Color {
        switch kind {
        case .warm: return hot
        case .cold: return cold
        case .wet: return rainSeries
        case .dry: return Color(red: 0.48, green: 0.50, blue: 0.54)
        case .muggy: return Color(red: 0.52, green: 0.38, blue: 0.68)
        case .muggyLow: return wetBulb
        case .neutral: return Color.secondary
        }
    }

    static func badgeBackground(_ kind: AnomalyKind) -> Color {
        badgeForeground(kind).opacity(0.14)
    }
}

/// Full-bleed sky gradient derived from the current WMO code and day/night.
enum Atmosphere {
    struct Colors: Equatable {
        let top: Color
        let mid: Color
        let bottom: Color
        let foreground: Color
        let secondaryForeground: Color
    }

    static func colors(code: Int?, isDay: Bool) -> Colors {
        let family = family(for: code)
        let sky = skyColors(family: family, isDay: isDay)
        return Colors(
            top: sky.top,
            mid: sky.mid,
            bottom: sky.mid,
            foreground: .white,
            secondaryForeground: Color.white.opacity(0.84))
    }

    /// Day and night skies from the website hero. Type stays light on both.
    private static func skyColors(family: Family, isDay: Bool) -> (top: Color, mid: Color) {
        if isDay {
            switch family {
            case .clear: return (hex(0x165EA8), hex(0x2C78BC))
            case .cloudy: return (hex(0x3D5168), hex(0x5D738C))
            case .fog: return (hex(0x4A5563), hex(0x6D7886))
            case .rain: return (hex(0x1D4D6E), hex(0x3D7396))
            case .snow: return (hex(0x3C5C78), hex(0x6E8EAA))
            case .storm: return (hex(0x2A2444), hex(0x51486E))
            }
        }
        switch family {
        case .clear: return (hex(0x071428), hex(0x16325C))
        case .cloudy: return (hex(0x121820), hex(0x243044))
        case .fog: return (hex(0x1A1E24), hex(0x2C333C))
        case .rain: return (hex(0x0C1A2E), hex(0x1A3350))
        case .snow: return (hex(0x15202C), hex(0x2A3C50))
        case .storm: return (hex(0x140E22), hex(0x2A2044))
        }
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    private enum Family {
        case clear, cloudy, rain, snow, storm, fog
    }

    private static func family(for code: Int?) -> Family {
        guard let code else { return .cloudy }
        switch code {
        case 0, 1: return .clear
        case 2, 3: return .cloudy
        case 45, 48: return .fog
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        default:
            if code >= 50 && code < 70 { return .rain }
            if code >= 70 && code < 90 { return .snow }
            return .cloudy
        }
    }
}

struct AtmosphereBackground: View {
    let colors: Atmosphere.Colors

    var body: some View {
        LinearGradient(
            colors: [colors.top, colors.mid, colors.bottom],
            startPoint: .top,
            endPoint: .bottom)
        .overlay {
            // Soft vignette so white type stays readable on bright skies.
            LinearGradient(
                colors: [
                    Color.black.opacity(0.08),
                    Color.clear,
                    Color.black.opacity(0.04),
                ],
                startPoint: .top,
                endPoint: .bottom)
        }
        .ignoresSafeArea(edges: .top)
    }
}

extension Prefs.ThemeOverride {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
