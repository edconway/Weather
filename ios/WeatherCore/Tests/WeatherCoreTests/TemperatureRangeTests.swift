import XCTest
@testable import WeatherCore

final class TemperatureRangeTests: XCTestCase {

    private let seed = TemperatureGaugeSeed(locationID: "london", day: "2026-11-15")

    func testDomainPadsByAtLeastTwoDegreesAndRoundsOutward() {
        let inside = TemperatureRangeLayout.domain(for: TemperatureRangeData(
            todayLow: 7, todayHigh: 10, averageLow: 5, averageHigh: 12))
        XCTAssertEqual(inside.lower, 3)
        XCTAssertEqual(inside.upper, 14)

        let narrow = TemperatureRangeLayout.domain(for: TemperatureRangeData(todayLow: 9, todayHigh: 9.5))
        XCTAssertEqual(narrow.lower, 7)
        XCTAssertEqual(narrow.upper, 12)
    }

    func testDomainUnionsTheSharedOverride() {
        let domain = TemperatureRangeLayout.domain(for: TemperatureRangeData(
            todayLow: 10, todayHigh: 12, scaleOverride: -5...30))
        XCTAssertEqual(domain.lower, -9)
        XCTAssertEqual(domain.upper, 34)
    }

    func testDomainIncludesACurrentReadingOutsideToday() {
        let domain = TemperatureRangeLayout.domain(for: TemperatureRangeData(
            todayLow: 3, todayHigh: 12, current: 13))
        XCTAssertLessThanOrEqual(domain.lower, 3)
        XCTAssertGreaterThanOrEqual(domain.upper, 13)
    }

    func testInvertedInputIsSwapped() {
        let data = TemperatureRangeData(
            todayLow: 12, todayHigh: 3, averageLow: 14, averageHigh: 6).normalized()
        XCTAssertEqual(data.todayLow, 3)
        XCTAssertEqual(data.todayHigh, 12)
        XCTAssertEqual(data.averageLow, 6)
        XCTAssertEqual(data.averageHigh, 14)
    }

    func testXMappingUsesTheInsetAndClampsToTheTrack() {
        let domain = TemperatureScaleDomain(lower: 0, upper: 20)
        XCTAssertEqual(TemperatureRangeLayout.x(temperature: 0, domain: domain, inset: 22, usableWidth: 200), 22)
        XCTAssertEqual(TemperatureRangeLayout.x(temperature: 20, domain: domain, inset: 22, usableWidth: 200), 222)
        XCTAssertEqual(TemperatureRangeLayout.x(temperature: 10, domain: domain, inset: 22, usableWidth: 200), 122)
        XCTAssertEqual(TemperatureRangeLayout.x(temperature: -5, domain: domain, inset: 22, usableWidth: 200), 22)
        XCTAssertEqual(TemperatureRangeLayout.x(temperature: 40, domain: domain, inset: 22, usableWidth: 200), 222)
    }

    func testBracketLegsUseTheAveragePositions() {
        let placed = TemperatureRangeLayout.placement(
            data: TemperatureRangeData(todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12),
            style: .hero, unit: .celsius, width: 320, seed: seed, stackedLabels: false)
        let low = TemperatureRangeLayout.x(
            temperature: 5, domain: placed.domain, inset: placed.inset, usableWidth: placed.usableWidth)
        let high = TemperatureRangeLayout.x(
            temperature: 12, domain: placed.domain, inset: placed.inset, usableWidth: placed.usableWidth)
        XCTAssertEqual(placed.bracketLowX ?? -1, low, accuracy: 0.5)
        XCTAssertEqual(placed.bracketHighX ?? -1, high, accuracy: 0.5)
        XCTAssertEqual(placed.bracketCurves[0].start.x, low, accuracy: 0.5)
        XCTAssertEqual(placed.bracketCurves[0].end.x, low, accuracy: 0.5)
        XCTAssertEqual(placed.bracketCurves[2].start.x, high, accuracy: 0.5)
        XCTAssertEqual(placed.bracketCurves[2].end.x, high, accuracy: 0.5)
        XCTAssertEqual(placed.bracketLegEnd, placed.trackTop - 4, accuracy: 0.5)
    }

    func testThreeDegreesIsBlueAndThirtyIsRed() {
        let cool = TemperatureColorScale.color(celsius: 3)
        let hot = TemperatureColorScale.color(celsius: 30)
        XCTAssertGreaterThan(cool.blue, cool.red)
        XCTAssertGreaterThan(hot.red, hot.blue)
        XCTAssertEqual(hot.red, 1, accuracy: 0.01)
        XCTAssertEqual(hot.green, 90.0 / 255, accuracy: 0.01)
        XCTAssertEqual(hot.blue, 78.0 / 255, accuracy: 0.01)
        XCTAssertEqual(TemperatureColorScale.color(celsius: -40).blue, TemperatureColorScale.color(celsius: -10).blue, accuracy: 0.001)
        XCTAssertEqual(TemperatureColorScale.color(celsius: 50).red, hot.red, accuracy: 0.001)
    }

    func testColourDoesNotDependOnTheDomain() {
        let coldDay = TemperatureColorScale.gradientStops(domain: TemperatureScaleDomain(lower: -20, upper: 5))
        let hotDay = TemperatureColorScale.gradientStops(domain: TemperatureScaleDomain(lower: 20, upper: 40))
        XCTAssertGreaterThan(coldDay[0].color.blue, coldDay[0].color.red)
        XCTAssertGreaterThan(hotDay.last!.color.red, hotDay.last!.color.blue)
    }

    func testBarColourFollowsAbsoluteTemperature() {
        let mild = TemperatureColorScale.stops(from: 7, to: 10)
        XCTAssertGreaterThan(mild[0].color.blue, mild[0].color.red)
        XCTAssertGreaterThan(mild.last!.color.blue, mild.last!.color.red)

        let hot = TemperatureColorScale.stops(from: 28, to: 34)
        XCTAssertGreaterThan(hot[0].color.red, hot[0].color.blue)
        XCTAssertEqual(hot.last!.color.red, TemperatureColorScale.color(celsius: 30).red, accuracy: 0.001)

        let freezing = TemperatureColorScale.stops(from: -20, to: -10)
        XCTAssertEqual(freezing[0].color.blue, TemperatureRGB(hex: 0x2F8CFF).blue, accuracy: 0.001)
        XCTAssertEqual(freezing.last!.color.red, TemperatureRGB(hex: 0x2F8CFF).red, accuracy: 0.001)

        let full = TemperatureColorScale.stops(from: -10, to: 30)
        XCTAssertEqual(full[0].color.red, TemperatureRGB(hex: 0x2F8CFF).red, accuracy: 0.001)
        XCTAssertEqual(full.last!.color.red, TemperatureRGB(hex: 0xFF5A4E).red, accuracy: 0.001)
        XCTAssertTrue(full.contains { abs($0.location - (24.0 / 40.0)) < 0.001 })
    }

    func testVoiceOverReadsColderWarmerAndInLine() {
        XCTAssertEqual(
            TemperatureRangeLayout.voiceOver(TemperatureRangeData(
                todayLow: 7, todayHigh: 10, averageLow: 5, averageHigh: 12), unit: .celsius),
            "Today 7 degrees to 10 degrees. Historic average 5 degrees to 12 degrees. In line with the historic average.")
        XCTAssertEqual(
            TemperatureRangeLayout.voiceOver(TemperatureRangeData(
                todayLow: -4, todayHigh: 2, averageLow: 6, averageHigh: 12), unit: .celsius),
            "Today minus 4 degrees to 2 degrees. Historic average 6 degrees to 12 degrees. Colder than the historic average.")
        XCTAssertEqual(
            TemperatureRangeLayout.voiceOver(TemperatureRangeData(
                todayLow: 24, todayHigh: 31, current: 28, averageLow: 14, averageHigh: 20), unit: .celsius),
            "Today 24 degrees to 31 degrees. Now 28 degrees. Historic average 14 degrees to 20 degrees. Warmer than the historic average.")
    }

    func testVoiceOverUsesTheRealCurrentValueAndOmitsAMissingAverage() {
        let sentence = TemperatureRangeLayout.voiceOver(TemperatureRangeData(
            todayLow: 3, todayHigh: 12, current: 13), unit: .celsius)
        XCTAssertEqual(sentence, "Today 3 degrees to 12 degrees. Now 13 degrees.")
        XCTAssertFalse(sentence.contains("Historic"))
    }

    func testFahrenheitLabelsRoundWithoutChangingTheLayoutDomain() {
        XCTAssertEqual(TemperatureRangeLayout.roundedDegrees(0, unit: .fahrenheit), 32)
        XCTAssertEqual(TemperatureRangeLayout.degreeLabel(10, unit: .fahrenheit), "50°")
        let celsius = TemperatureRangeLayout.domain(for: TemperatureRangeData(todayLow: 0, todayHigh: 10))
        let labeled = TemperatureRangeLayout.placement(
            data: TemperatureRangeData(todayLow: 0, todayHigh: 10, current: 10),
            style: .hero, unit: .fahrenheit, width: 320, seed: seed, stackedLabels: false)
        XCTAssertEqual(labeled.domain, celsius)
        XCTAssertEqual(labeled.highText, "50°")
    }

    func testWobbleIsStableForTheSamePlaceAndDate() {
        let first = TemperatureRangeLayout.wobble(seed: seed)
        let second = TemperatureRangeLayout.wobble(seed: seed)
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, TemperatureRangeLayout.wobble(
            seed: TemperatureGaugeSeed(locationID: "london", day: "2026-11-16")))
        XCTAssertTrue(first.allSatisfy { abs($0) >= 1 && abs($0) <= 2 })
    }

    func testArrowEndsJustOutsideTheRingAndMissesTheLabels() throws {
        let placed = TemperatureRangeLayout.placement(
            data: TemperatureRangeData(todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12),
            style: .hero, unit: .celsius, width: 320, seed: seed, stackedLabels: false)
        let arrow = try XCTUnwrap(placed.arrow)
        let dot = try XCTUnwrap(placed.dot)
        let distance = hypot(arrow.tip.x - dot.x, arrow.tip.y - dot.y)
        let outer = placed.dotRadius + TemperatureRangeLayout.ringWidth
        XCTAssertGreaterThan(distance, outer)
        XCTAssertLessThan(distance, outer + 4)
        let towardX = dot.x - arrow.tip.x
        let towardY = dot.y - arrow.tip.y
        let toward = hypot(towardX, towardY)
        let dotProduct = (arrow.finalTangent.x * towardX + arrow.finalTangent.y * towardY) / toward
        XCTAssertGreaterThan(dotProduct, 0.95)
        let blocked = [placed.lowLabel, placed.highLabel].compactMap { $0 }
        for sample in arrow.samples {
            XCTAssertFalse(blocked.contains { $0.contains(sample) })
        }
    }

    func testAccessibilitySizeDropsTheArrow() {
        let placed = TemperatureRangeLayout.placement(
            data: TemperatureRangeData(todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12),
            style: .hero, unit: .celsius, width: 320, seed: seed, stackedLabels: true, allowArrow: false)
        XCTAssertNil(placed.arrow)
        XCTAssertNotNil(placed.combinedLabel)
        XCTAssertNil(placed.lowLabel)
    }

    func testNarrowBarKeepsAMinimumWidth() {
        let placed = TemperatureRangeLayout.placement(
            data: TemperatureRangeData(todayLow: 9, todayHigh: 9.5, current: 9.2, scaleOverride: -20...40),
            style: .hero, unit: .celsius, width: 320, seed: seed, stackedLabels: false)
        XCTAssertGreaterThanOrEqual(placed.barEnd - placed.barStart, 9)
    }

    func testCurrentOutsideTodayIsNotClampedToTheBar() {
        let placed = TemperatureRangeLayout.placement(
            data: TemperatureRangeData(todayLow: 3, todayHigh: 12, current: 13, averageLow: 6, averageHigh: 12),
            style: .hero, unit: .celsius, width: 320, seed: seed, stackedLabels: false)
        let dot = placed.dot?.x ?? 0
        XCTAssertGreaterThan(dot, placed.barEnd)
        XCTAssertLessThanOrEqual(dot, placed.inset + placed.usableWidth)
    }

    func testNotesAreCursiveWording() {
        let phone = TemperatureRangeLayout.placement(
            data: TemperatureRangeData(todayLow: 9, todayHigh: 28, current: 28, averageLow: 4, averageHigh: 16),
            style: .hero, unit: .celsius, width: 360, seed: seed, stackedLabels: false)
        XCTAssertEqual(phone.historicText, "historic average 4°–16°")
        XCTAssertEqual(phone.nowText, "temperature now")
        XCTAssertNotNil(phone.arrow)
        XCTAssertFalse(phone.bracketCurves.isEmpty)

        let watch = TemperatureRangeLayout.placement(
            data: TemperatureRangeData(todayLow: 9, todayHigh: 28, current: 28, averageLow: 4, averageHigh: 16),
            style: .widget, unit: .celsius, width: 170, seed: seed, stackedLabels: false)
        XCTAssertEqual(watch.historicText, "typical range")
        XCTAssertEqual(watch.nowText, "temperature now")
        XCTAssertNil(watch.lowLabel)
        XCTAssertNotNil(watch.arrow)
        XCTAssertFalse(watch.bracketCurves.isEmpty)
    }

    func testRowStyleIsTheBarAndDotOnly() {
        let placed = TemperatureRangeLayout.placement(
            data: TemperatureRangeData(todayLow: 7, todayHigh: 10, current: 8, averageLow: 5, averageHigh: 12),
            style: .row, unit: .celsius, width: 320, seed: seed, stackedLabels: false)
        XCTAssertNil(placed.bracketLowX)
        XCTAssertNil(placed.arrow)
        XCTAssertNil(placed.lowLabel)
        XCTAssertNotNil(placed.dot)
        XCTAssertEqual(placed.height, 14, accuracy: 0.1)
    }
}
