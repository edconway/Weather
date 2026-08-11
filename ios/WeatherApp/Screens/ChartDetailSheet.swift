import SwiftUI
import WeatherCore

/// Full-screen presentation of a single chart with a taller plot and the
/// explanatory subtitle prose that used to live under each section header.
struct ChartDetailSheet: View {
    enum Kind: Identifiable, Equatable {
        case hourlyTemp
        case dailyTemp
        case hourlyWetBulb
        case dailyWetBulb
        case hourlyRain
        case dailyRain
        case ytdRain
        case climate

        var id: String {
            switch self {
            case .hourlyTemp: return "hourly-temp"
            case .dailyTemp: return "daily-temp"
            case .hourlyWetBulb: return "hourly-wetbulb"
            case .dailyWetBulb: return "daily-wetbulb"
            case .hourlyRain: return "hourly-rain"
            case .dailyRain: return "daily-rain"
            case .ytdRain: return "ytd-rain"
            case .climate: return "climate"
            }
        }

        var title: String {
            switch self {
            case .hourlyTemp: return "48-Hour Temperature"
            case .dailyTemp: return "14-Day Temperature"
            case .hourlyWetBulb: return "48-Hour Wet Bulb"
            case .dailyWetBulb: return "14-Day Wet Bulb"
            case .hourlyRain: return "48-Hour Rainfall"
            case .dailyRain: return "14-Day Rainfall"
            case .ytdRain: return "Year-to-Date Rainfall"
            case .climate: return "Climate Overview"
            }
        }
    }

    let kind: Kind
    let store: WeatherStore
    @Environment(\.dismiss) private var dismiss
    @State private var scrubCoordinator = ActiveScrubCoordinator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    chart
                }
                .padding(20)
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .environment(scrubCoordinator)
    }

    private var timeZone: TimeZone { store.locationTimeZone }

    private var subtitle: String {
        switch kind {
        case .hourlyTemp: return Subtitles.hourlyTemp(store)
        case .dailyTemp: return Subtitles.dailyTemp(store)
        case .hourlyWetBulb: return Subtitles.hourlyWetBulb(store)
        case .dailyWetBulb: return Subtitles.dailyWetBulb(store)
        case .hourlyRain: return Subtitles.hourlyRain(store)
        case .dailyRain: return Subtitles.dailyRain(store)
        case .ytdRain: return Subtitles.ytdRain(store)
        case .climate: return Subtitles.climate(store)
        }
    }

    @ViewBuilder
    private var chart: some View {
        switch kind {
        case .hourlyTemp:
            HourlyTempChart(
                points: store.hourlyPoints, series: .temperature,
                formatter: store.formatter, timeZone: timeZone, expanded: true)
        case .dailyTemp:
            DailyTempChart(
                points: store.dailyPoints, series: .temperature,
                formatter: store.formatter, timeZone: timeZone, expanded: true)
        case .hourlyWetBulb:
            HourlyTempChart(
                points: store.hourlyPoints, series: .wetBulb,
                formatter: store.formatter, timeZone: timeZone, expanded: true)
        case .dailyWetBulb:
            DailyTempChart(
                points: store.dailyPoints, series: .wetBulb,
                formatter: store.formatter, timeZone: timeZone, expanded: true)
        case .hourlyRain:
            HourlyRainChart(
                points: store.hourlyPoints,
                formatter: store.formatter, timeZone: timeZone, expanded: true)
        case .dailyRain:
            DailyRainChart(
                points: store.dailyPoints,
                formatter: store.formatter, timeZone: timeZone, expanded: true)
        case .ytdRain:
            if let series = store.ytdSeries {
                YTDRainChart(
                    series: series, formatter: store.formatter,
                    thisYear: store.ytdRain?.thisYear ?? 0,
                    timeZone: timeZone, expanded: true)
            } else {
                ChartPlaceholder(message: "Loading year-to-date rainfall…")
            }
        case .climate:
            if let climatology = store.climatology {
                ClimateChart(
                    points: ChartSeries.climate(climatology),
                    formatter: store.formatter, expanded: true)
            } else {
                ChartPlaceholder(message: "Loading climate data…")
            }
        }
    }
}
