import Foundation
import WeatherCore

/// Which of the 14 day labels to draw.
///
/// "Today" is bold and wider than a weekday abbreviation, so showing every
/// other day *plus* today collides whenever today lands on an odd index.
enum DayLabelDensity {
    static func shows(
        _ point: ChartSeries.DailyPoint, in points: [ChartSeries.DailyPoint]
    ) -> Bool {
        if point.isToday { return true }
        guard let todayIndex = points.first(where: \.isToday)?.id else {
            return point.id % 2 == 0
        }
        // Never label a day directly beside "Today".
        if abs(point.id - todayIndex) == 1 { return false }
        // Alternate away from today so the spacing stays even on both sides.
        return abs(point.id - todayIndex) % 2 == 0
    }
}
