import Foundation

/// The averaging helpers the web app defines inline (`arrAvg`, `arrMedian`,
/// `arrP90`). Kept in one place so every derivation rounds and skips nulls the
/// same way.
public enum Stats {
    /// Mean, or `nil` for an empty pool. Mirrors `arrAvg`.
    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Mean with `0` for an empty pool — what `deriveDailyRain` uses.
    public static func meanOrZero(_ values: [Double]) -> Double {
        mean(values) ?? 0
    }

    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    /// 90th percentile by `sorted[floor(n * 0.9)]` — the web app's exact
    /// (nearest-rank-ish) definition, not a interpolating percentile.
    public static func p90(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int(Double(sorted.count) * 0.9)
        return index < sorted.count ? sorted[index] : (sorted.last ?? 0)
    }

    /// Share of values at or above 0.1 mm — the app's "wet" threshold.
    public static func wetShare(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.filter { $0 >= 0.1 }.count) / Double(values.count)
    }
}

extension Array {
    /// Bounds-checked lookup. The API's parallel arrays are usually the same
    /// length, but a short array must degrade to "no value" rather than crash.
    func at(_ index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension Array {
    /// Flattens `[T?]` lookups: `array.value(at: i)` is `nil` both when the
    /// index is out of range and when the element itself is `null`.
    func value<T>(at index: Int) -> T? where Element == T? {
        indices.contains(index) ? self[index] : nil
    }
}
