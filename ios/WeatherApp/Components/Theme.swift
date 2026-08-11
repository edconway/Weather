import SwiftUI
import WeatherCore

/// The web app's palette, translated to SwiftUI and made dark-mode aware.
///
/// PLAN DEVIATION §1.4.4: the time-of-day ambience tinting (`applyTimeAmbience`)
/// is dropped; light/dark follows the system with an in-app override.
enum Palette {
    static let accent = Color(red: 0.40, green: 0.49, blue: 0.92)

    /// Panel cap colours, matching the web's `panel-cap` inline styles.
    static let temperature = Color(red: 0.77, green: 0.36, blue: 0.32)   // #c45c52
    static let wetBulb = Color(red: 0.23, green: 0.62, blue: 0.58)       // #3a9f95
    static let rain = Color(red: 0.33, green: 0.41, blue: 0.72)          // #5568b8

    /// Chart series.
    static let hot = Color(red: 0.85, green: 0.33, blue: 0.28)
    static let cold = Color(red: 0.27, green: 0.53, blue: 0.82)
    static let rainSeries = Color(red: 0.29, green: 0.45, blue: 0.85)
    static let historical = Color.secondary

    static func badgeForeground(_ kind: AnomalyKind) -> Color {
        switch kind {
        case .warm: return Color(red: 0.80, green: 0.36, blue: 0.20)
        case .cold: return Color(red: 0.20, green: 0.47, blue: 0.78)
        case .wet: return Color(red: 0.16, green: 0.50, blue: 0.73)
        case .dry: return Color(red: 0.44, green: 0.47, blue: 0.52)
        case .muggy: return Color(red: 0.55, green: 0.36, blue: 0.72)
        case .muggyLow: return Color(red: 0.29, green: 0.55, blue: 0.55)
        case .neutral: return Color.secondary
        }
    }

    static func badgeBackground(_ kind: AnomalyKind) -> Color {
        badgeForeground(kind).opacity(0.14)
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
