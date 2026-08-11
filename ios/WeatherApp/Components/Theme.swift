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
        if !isDay {
            return Colors(
                top: Color(red: 0.05, green: 0.08, blue: 0.18),
                mid: Color(red: 0.10, green: 0.14, blue: 0.28),
                bottom: Color(red: 0.16, green: 0.18, blue: 0.30),
                foreground: .white,
                secondaryForeground: Color.white.opacity(0.78))
        }
        switch family {
        case .clear:
            return Colors(
                top: Color(red: 0.35, green: 0.62, blue: 0.95),
                mid: Color(red: 0.55, green: 0.78, blue: 0.98),
                bottom: Color(red: 0.82, green: 0.90, blue: 0.98),
                foreground: Color(red: 0.08, green: 0.14, blue: 0.28),
                secondaryForeground: Color(red: 0.18, green: 0.28, blue: 0.42).opacity(0.85))
        case .cloudy:
            return Colors(
                top: Color(red: 0.55, green: 0.64, blue: 0.76),
                mid: Color(red: 0.70, green: 0.76, blue: 0.84),
                bottom: Color(red: 0.88, green: 0.90, blue: 0.93),
                foreground: Color(red: 0.12, green: 0.16, blue: 0.24),
                secondaryForeground: Color(red: 0.28, green: 0.32, blue: 0.40).opacity(0.85))
        case .rain:
            return Colors(
                top: Color(red: 0.28, green: 0.38, blue: 0.52),
                mid: Color(red: 0.42, green: 0.52, blue: 0.64),
                bottom: Color(red: 0.62, green: 0.70, blue: 0.78),
                foreground: .white,
                secondaryForeground: Color.white.opacity(0.82))
        case .snow:
            return Colors(
                top: Color(red: 0.62, green: 0.72, blue: 0.86),
                mid: Color(red: 0.78, green: 0.84, blue: 0.92),
                bottom: Color(red: 0.92, green: 0.94, blue: 0.97),
                foreground: Color(red: 0.12, green: 0.18, blue: 0.30),
                secondaryForeground: Color(red: 0.28, green: 0.34, blue: 0.44).opacity(0.85))
        case .storm:
            return Colors(
                top: Color(red: 0.18, green: 0.20, blue: 0.32),
                mid: Color(red: 0.30, green: 0.32, blue: 0.44),
                bottom: Color(red: 0.48, green: 0.46, blue: 0.52),
                foreground: .white,
                secondaryForeground: Color.white.opacity(0.82))
        case .fog:
            return Colors(
                top: Color(red: 0.58, green: 0.62, blue: 0.68),
                mid: Color(red: 0.72, green: 0.74, blue: 0.78),
                bottom: Color(red: 0.86, green: 0.87, blue: 0.88),
                foreground: Color(red: 0.16, green: 0.18, blue: 0.22),
                secondaryForeground: Color(red: 0.32, green: 0.34, blue: 0.38).opacity(0.85))
        }
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
