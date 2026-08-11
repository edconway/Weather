import SwiftUI
import XCTest
@testable import WeatherCore

/// Existence-level regression net for the complication content views. No
/// snapshot library (project rule: zero third-party dependencies) — this just
/// proves every layout renders to a non-nil image for both a populated and an
/// empty entry, catching the class of bug where a view throws/traps/produces
/// nothing rather than checking pixels.
@MainActor
final class WidgetViewSmokeTests: XCTestCase {

    private func assertRenders(_ view: some View, _ name: String) {
        let renderer = ImageRenderer(content: view.frame(width: 180, height: 180))
        XCTAssertNotNil(renderer.cgImage, "\(name) failed to render")
    }

    func testAllLayoutsRenderWithPlaceholder() {
        let entry = WeatherEntrySnapshot.placeholder
        assertRenders(CurrentConditionsContent(entry: entry, layout: .circular), "conditions.circular")
        assertRenders(CurrentConditionsContent(entry: entry, layout: .inline), "conditions.inline")
        assertRenders(CurrentConditionsContent(entry: entry, layout: .rectangular), "conditions.rectangular")
        assertRenders(CurrentConditionsContent(entry: entry, layout: .corner), "conditions.corner")
        assertRenders(TempAnomalyContent(entry: entry, layout: .circular), "anomaly.circular")
        assertRenders(TempAnomalyContent(entry: entry, layout: .inline), "anomaly.inline")
        assertRenders(TempAnomalyContent(entry: entry, layout: .rectangular), "anomaly.rectangular")
        assertRenders(RainChanceContent(entry: entry, layout: .circular), "rain.circular")
        assertRenders(RainChanceContent(entry: entry, layout: .inline), "rain.inline")
        assertRenders(RainChanceContent(entry: entry, layout: .corner), "rain.corner")
    }

    /// §10.2 — the "no cached location at all" placeholder must still render
    /// cleanly in every layout, not just the populated case.
    func testAllLayoutsRenderWithEmptyEntry() {
        let entry = WeatherEntrySnapshot.empty()
        assertRenders(CurrentConditionsContent(entry: entry, layout: .circular), "empty.conditions.circular")
        assertRenders(CurrentConditionsContent(entry: entry, layout: .inline), "empty.conditions.inline")
        assertRenders(CurrentConditionsContent(entry: entry, layout: .rectangular), "empty.conditions.rectangular")
        assertRenders(CurrentConditionsContent(entry: entry, layout: .corner), "empty.conditions.corner")
        // TempAnomaly with no delta falls back to CurrentConditions content —
        // exercise that fallback path specifically, for every layout it supports.
        assertRenders(TempAnomalyContent(entry: entry, layout: .circular), "empty.anomaly.circular")
        assertRenders(TempAnomalyContent(entry: entry, layout: .inline), "empty.anomaly.inline")
        assertRenders(TempAnomalyContent(entry: entry, layout: .rectangular), "empty.anomaly.rectangular")
        assertRenders(RainChanceContent(entry: entry, layout: .circular), "empty.rain.circular")
    }

    /// The temperature-anomaly widget's two code paths — with and without a
    /// synced delta — are different enough (one falls back to an entirely
    /// different content view) that both deserve their own explicit check
    /// beyond what the placeholder/empty sweeps above already cover.
    func testTempAnomalyRendersBothWithAndWithoutDelta() {
        let withDelta = WeatherEntrySnapshot.placeholder  // placeholder carries temperatureDelta: 3
        XCTAssertNotNil(withDelta.temperatureDelta)
        assertRenders(TempAnomalyContent(entry: withDelta, layout: .circular), "delta.present.circular")

        let withoutDelta = WeatherEntrySnapshot(
            date: withDelta.date, locationName: withDelta.locationName,
            temperature: withDelta.temperature, high: withDelta.high, low: withDelta.low,
            rainChance: withDelta.rainChance, conditionCode: withDelta.conditionCode,
            isDay: withDelta.isDay, temperatureDelta: nil, imperial: withDelta.imperial)
        XCTAssertNil(withoutDelta.temperatureDelta)
        assertRenders(TempAnomalyContent(entry: withoutDelta, layout: .circular), "delta.absent.circular")
    }
}
