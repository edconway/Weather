import Charts
import SwiftUI
import WeatherCore

/// Minute rain from Apple. Shown only when `displayMinutes` is non-empty,
/// so an hourly Open-Meteo estimate is never drawn as a minute curve.
struct NextHourCard: View {
    let minutes: [AppleMinutePoint]
    /// Neighbourhood, street, or coordinates of the point these minutes cover.
    let placeLabel: String
    let attribution: AppleWeatherAttribution?
    let formatter: UnitFormatter
    let timeZone: TimeZone
    /// True when Apple's minutes include rain, so the card reads ahead of the hourly estimate.
    var emphasize: Bool = false

    private var summary: (headline: String, detail: String) {
        AppleWeatherStatus.summary(minutes: minutes, timeZone: timeZone, formatter: formatter)
    }

    private var peak: Double {
        minutes.map(\.intensityMillimetresPerHour).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("NEXT HOUR")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Apple Weather · minute by minute")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !placeLabel.isEmpty {
                Label(placeLabel, systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                    .labelStyle(.titleAndIcon)
            }
            Text(summary.headline)
                .font(emphasize ? .title2.weight(.semibold) : .title3.weight(.semibold))
            Text(summary.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart(minutes) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    y: .value("Rate", formatter.precipitationValue(point.intensityMillimetresPerHour))
                )
                .foregroundStyle(Palette.rainSeries.opacity(0.22))
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Rate", formatter.precipitationValue(point.intensityMillimetresPerHour))
                )
                .foregroundStyle(Palette.rainSeries)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYScale(domain: 0 ... yTop)
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute, count: 15)) { value in
                    AxisGridLine()
                    if let label = minuteAxisLabel(for: value) {
                        AxisValueLabel(label)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(formatter.precipitationAxis(displayValue: number))
                        }
                    }
                }
            }
            .frame(height: 118)

            if let attribution {
                AppleAttributionView(attribution: attribution)
            }
        }
        .padding(14)
        .background(
            emphasize ? Palette.rainSeries.opacity(0.12) : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if emphasize {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.rainSeries.opacity(0.45), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySentence)
    }

    private var accessibilitySentence: String {
        let place = placeLabel.isEmpty ? "" : "\(placeLabel). "
        return "\(place)\(summary.headline). \(summary.detail). Apple Weather, minute by minute."
    }

    private var yTop: Double {
        let displayed = formatter.precipitationValue(peak)
        return max(displayed * 1.25, formatter.precipitationValue(0.5))
    }

    /// Hour:minute label for a date axis value. `AxisValueLabel` takes the
    /// string directly; a trailing closure that does not return a view is
    /// type-checked as `() -> ()` and rejected.
    private func minuteAxisLabel(for value: AxisValue) -> String? {
        guard let date = value.as(Date.self) else { return nil }
        var style = Date.FormatStyle().hour().minute()
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

struct AppleAlertsList: View {
    let alerts: [AppleWeatherAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(alerts) { alert in
                Link(destination: alert.detailsURL) {
                    Label(alert.summary, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
