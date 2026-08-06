import SwiftUI
import WeatherCore
import WidgetKit

/// §10.1 — three widgets, each mapping its supported families onto the shared
/// content views in `WeatherCore`.

struct CurrentConditionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentConditions", provider: WeatherTimelineProvider()) { entry in
            CurrentConditionsView(entry: entry.snapshot)
                .widgetURL(AppConfig.todayDeepLink)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Conditions")
        .description("Current temperature and conditions.")
        .supportedFamilies([
            .accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular
        ])
    }
}

private struct CurrentConditionsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntrySnapshot

    var body: some View {
        switch family {
        case .accessoryCorner:
            CurrentConditionsContent(entry: entry, layout: .corner)
        case .accessoryInline:
            CurrentConditionsContent(entry: entry, layout: .inline)
        case .accessoryRectangular:
            CurrentConditionsContent(entry: entry, layout: .rectangular)
        default:
            CurrentConditionsContent(entry: entry, layout: .circular)
        }
    }
}

struct TempAnomalyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TempAnomaly", provider: WeatherTimelineProvider()) { entry in
            TempAnomalyView(entry: entry.snapshot)
                .widgetURL(AppConfig.todayDeepLink)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("vs Normal")
        .description("How today compares with the historical average.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

private struct TempAnomalyView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntrySnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            TempAnomalyContent(entry: entry, layout: .inline)
        case .accessoryRectangular:
            TempAnomalyContent(entry: entry, layout: .rectangular)
        default:
            TempAnomalyContent(entry: entry, layout: .circular)
        }
    }
}

struct RainChanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RainChance", provider: WeatherTimelineProvider()) { entry in
            RainChanceView(entry: entry.snapshot)
                .widgetURL(AppConfig.todayDeepLink)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Rain Chance")
        .description("Today's chance of rain.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

private struct RainChanceView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntrySnapshot

    var body: some View {
        switch family {
        case .accessoryCorner:
            RainChanceContent(entry: entry, layout: .corner)
        case .accessoryInline:
            RainChanceContent(entry: entry, layout: .inline)
        default:
            RainChanceContent(entry: entry, layout: .circular)
        }
    }
}
