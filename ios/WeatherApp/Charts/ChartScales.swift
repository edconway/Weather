import Foundation
import WeatherCore

/// Y-axis domains, ported from the web charts rather than left to Swift Charts'
/// automatic scaling.
///
/// Automatic scaling anchors temperature at 0°, which squashes a 10–26° day into
/// the top half of the plot and makes the historical band unreadable. The web
/// app pads the data range by ±2 instead (`_dims` callers in `charts.js`).
enum ChartScales {

    /// `floor(min) - 2 … ceil(max) + 2`, in display units.
    static func temperatureDomain(_ values: [Double?]) -> ClosedRange<Double> {
        let present = values.compactMap { $0 }.filter { $0.isFinite }
        guard let low = present.min(), let high = present.max() else { return 0...30 }
        let lower = (low - 2).rounded(.down)
        let upper = (high + 2).rounded(.up)
        // Degenerate data (a single repeated value) still needs a visible span.
        return lower < upper ? lower...upper : lower...(lower + 1)
    }

    /// `max(values, floor) * headroom`, matching the rain charts' `yMax`.
    static func rainDomain(
        _ values: [Double], floor minimum: Double, headroom: Double
    ) -> ClosedRange<Double> {
        let peak = max(values.filter(\.isFinite).max() ?? 0, minimum)
        return 0...(peak * headroom)
    }
}
