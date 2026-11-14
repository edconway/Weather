import Charts
import SwiftUI
import WeatherCore

/// Minute rain from Apple. Shown only when `displayMinutes` is non-empty,
/// so an hourly Open-Meteo estimate is never drawn as a minute curve.
struct NextHourCard: View {
    let minutes: [AppleMinutePoint]
    let attribution: AppleWeatherAttribution?
    let formatter: UnitFormatter
    let timeZone: TimeZone

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
            Text(summary.headline)
                .font(.title3.weight(.semibold))
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
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            var style = Date.FormatStyle().hour().minute()
                            style.timeZone = timeZone
                            Text(date.formatted(style))
                        }
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.headline). \(summary.detail). Apple Weather, minute by minute.")
    }

    private var yTop: Double {
        let displayed = formatter.precipitationValue(peak)
        return max(displayed * 1.25, formatter.precipitationValue(0.5))
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
