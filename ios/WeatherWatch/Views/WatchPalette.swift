import SwiftUI

/// Watch-local copy of the iOS app's chart colors (`WeatherApp/Components/Theme.swift`),
/// which lives in the iOS target and isn't reachable from here — same RGB
/// values, kept in sync by hand, so the two platforms read as one brand.
enum WatchPalette {
    static let hot = Color(red: 0.85, green: 0.33, blue: 0.28)
    static let cold = Color(red: 0.27, green: 0.53, blue: 0.82)
    static let rain = Color(red: 0.29, green: 0.45, blue: 0.85)
    /// The dashed "5-yr average" line and the band it draws — mirrors the iOS
    /// app's `Palette.historical`.
    static let historical = Color.gray
}
