import Charts
import SwiftUI
import WeatherCore

/// §8.4.5 — up to 48 hourly precipitation bars (±24 h around now). Probability
/// labels sit above forecast bars (≥20%); Swift Charts has no second y-axis.
struct HourlyRainChart: View {
    let points: [ChartSeries.HourlyPoint]
    let formatter: UnitFormatter
    let timeZone: TimeZone
    var detailText: String? = nil
    var onOpenDetail: (() -> Void)? = nil
    var expanded: Bool = false

    @State private var liveSelection: Date?
    @State private var selectedDate: Date?
    @State private var scrubID = UUID()

    private var nowDate: Date? { points.first(where: { !$0.isPast })?.date }

    private var nowPoint: ChartSeries.HourlyPoint? {
        points.first(where: { !$0.isPast })
    }

    private var selected: ChartSeries.HourlyPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    /// `yMax = max(precip, 0.5) * 1.25`, from `makeHourlyRainChart`.
    private var yDomain: ClosedRange<Double> {
        ChartScales.rainDomain(
            points.map { formatter.precipitationValue($0.precipitation) },
            floor: formatter.precipitationValue(0.5),
            headroom: 1.25)
    }

    private var nightRanges: [NightRange] {
        NightShading.ranges(in: points)
    }

    private var readout: ChartReadout {
        let point = selected ?? nowPoint
        guard let point else { return .placeholder }
        let primary = formatter.precipitationCompact(point.precipitation)
        let when: String
        if selected == nil || point.date == nowDate {
            when = "Now"
        } else {
            when = point.date.formatted(
                Date.FormatStyle().weekday(.abbreviated).hour(.defaultDigits(amPM: .abbreviated)),
                in: timeZone)
        }
        let tag = point.isPast ? " · actual" : (selected == nil ? "" : " · forecast")
        var context = "\(when)\(tag)"
        if !point.isPast, let probability = point.probability {
            context += " · \(probability)% chance"
        }
        if let p90 = point.rainP90, p90 > 0, point.precipitation >= p90 {
            context += " · heavier than usual"
        }
        return ChartReadout(primary: primary, context: context, primaryTint: Palette.rainSeries)
    }

    private var legend: [ChartLegendItem] { [] }

    var body: some View {
        ChartModule(
            eyebrow: "48-Hour Rainfall",
            readout: readout,
            detailText: detailText,
            legend: legend,
            onOpenDetail: onOpenDetail
        ) {
            plot
        }
    }

    private var plot: some View {
        Chart {
            ForEach(nightRanges) { range in
                RectangleMark(
                    xStart: .value("Night start", range.start),
                    xEnd: .value("Night end", range.end))
                .foregroundStyle(Color.secondary.opacity(ChartKit.nightShadeOpacity))
            }

            ForEach(points) { point in
                BarMark(
                    x: .value("Time", point.date, unit: .hour),
                    y: .value("Precipitation", formatter.precipitationValue(point.precipitation)))
                .foregroundStyle(Palette.rainSeries.opacity(point.isPast ? 0.45 : 1))
                .cornerRadius(1)
            }

            // Probability text above forecast bars only (≥20%), matching the web.
            ForEach(points) { point in
                if !point.isPast,
                   let probability = point.probability, probability >= 20 {
                    PointMark(
                        x: .value("Time", point.date, unit: .hour),
                        y: .value(
                            "Precipitation",
                            formatter.precipitationValue(point.precipitation)))
                    .opacity(0)
                    .annotation(position: .top, spacing: 2) {
                        Text("\(probability)%")
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(Palette.cold)
                    }
                }
            }

            if let nowDate {
                RuleMark(x: .value("Now", nowDate))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        NowCapsule()
                    }
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Palette.rainSeries.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXSelection(value: $liveSelection)
        .chartScrub($liveSelection)
        .stickyXSelection(
            id: scrubID, live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.timeString ?? "")
        .chartSelectionHaptic(selectedDate)
        .chartYScale(domain: yDomain)
        .chartYAxis { ChartAxes.precipitationYAxis(formatter: formatter) }
        .chartXAxis { ChartAxes.hourlyXAxis(timeZone: timeZone) }
        .frame(height: expanded ? ChartKit.hourlyHeight + 60 : ChartKit.hourlyHeight)
        .accessibilityLabel("48-hour rainfall chart")
    }
}

/// §8.4.6 — 14 daily precipitation bars with the §6.5 classification in the readout.
///
/// Categorical x for the same reason as `DailyTempChart`.
struct DailyRainChart: View {
    let points: [ChartSeries.DailyPoint]
    let formatter: UnitFormatter
    let timeZone: TimeZone
    var detailText: String? = nil
    var onOpenDetail: (() -> Void)? = nil
    var expanded: Bool = false

    @State private var liveSelection: String?
    @State private var selectedDate: String?
    @State private var scrubID = UUID()

    private var todayDateString: String? { points.first(where: \.isToday)?.dateString }

    private var todayPoint: ChartSeries.DailyPoint? {
        points.first(where: \.isToday)
    }

    private var selected: ChartSeries.DailyPoint? {
        points.first { $0.dateString == selectedDate }
    }

    /// `yMax = max(precip, 1) * 1.2`, from `makeDailyRainChart`.
    private var yDomain: ClosedRange<Double> {
        ChartScales.rainDomain(
            points.map { formatter.precipitationValue($0.precipitation) },
            floor: formatter.precipitationValue(1),
            headroom: 1.2)
    }

    private var readout: ChartReadout {
        let point = selected ?? todayPoint ?? points.first
        guard let point else { return .placeholder }
        let primary = formatter.precipitationCompact(point.precipitation)
        let when = selected == nil && point.isToday
            ? "Today"
            : point.label(timeZone: timeZone)
        let tag = point.isPast ? " · actual" : (selected == nil && point.isToday ? "" : " · forecast")
        var context = "\(when)\(tag)"
        if !point.isPast, let probability = point.probability {
            context += " · \(probability)% chance"
        }
        if let rainNormal = point.rainNormal {
            context += " · \(rainNormal.classification.text)"
        }
        return ChartReadout(primary: primary, context: context, primaryTint: Palette.rainSeries)
    }

    private var legend: [ChartLegendItem] { [] }

    var body: some View {
        ChartModule(
            eyebrow: "14-Day Rainfall",
            readout: readout,
            detailText: detailText,
            legend: legend,
            onOpenDetail: onOpenDetail
        ) {
            plot
        }
    }

    private var plot: some View {
        Chart {
            if let todayDateString {
                RectangleMark(x: .value("Today", todayDateString))
                    .foregroundStyle(Color.secondary.opacity(0.08))
            }

            ForEach(points) { point in
                BarMark(
                    x: .value("Day", point.dateString),
                    y: .value("Precipitation", formatter.precipitationValue(point.precipitation)),
                    width: .ratio(0.6))
                .foregroundStyle(point.isPast
                    ? Palette.rainSeries.opacity(0.4)
                    : Palette.rainClass(point.rainNormal?.classification))
                .cornerRadius(3)
            }

            // Value labels for days with measurable rain, matching the web.
            ForEach(points) { point in
                if point.precipitation >= 0.1 {
                    PointMark(
                        x: .value("Day", point.dateString),
                        y: .value(
                            "Precipitation",
                            formatter.precipitationValue(point.precipitation)))
                    .opacity(0)
                    .annotation(position: .top, spacing: 2) {
                        Text(formatter.precipitationCompact(point.precipitation))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.rainSeries)
                    }
                }
            }

            if let todayDateString {
                RuleMark(x: .value("Today", todayDateString))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .center) {
                        NowCapsule(label: "TODAY")
                    }
            }

            if let selected {
                RuleMark(x: .value("Selected", selected.dateString))
                    .foregroundStyle(Palette.rainSeries.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartXSelection(value: $liveSelection)
        .chartScrub($liveSelection)
        .stickyXSelection(
            id: scrubID, live: $liveSelection, sticky: $selectedDate,
            resetOn: points.first?.dateString ?? "")
        .chartSelectionHaptic(selectedDate)
        .chartXScale(domain: points.map(\.dateString))
        .chartYScale(domain: yDomain)
        .chartYAxis { ChartAxes.precipitationYAxis(formatter: formatter) }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 14)) { value in
                AxisValueLabel {
                    if let dateString = value.as(String.self),
                       let point = points.first(where: { $0.dateString == dateString }),
                       DayLabelDensity.shows(point, in: points) {
                        Text(point.label(timeZone: timeZone))
                            .font(.caption2.weight(point.isToday ? .bold : .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: expanded ? ChartKit.dailyHeight + 60 : ChartKit.dailyHeight)
        .accessibilityLabel("14-day rainfall chart")
    }
}
