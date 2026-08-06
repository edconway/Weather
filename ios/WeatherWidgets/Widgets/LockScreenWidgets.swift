import SwiftUI
import WeatherCore
import WidgetKit

/// Phase 8 — lock-screen accessories. These are the §10 views verbatim; the
/// point of putting them in `WeatherCore` was so this file stays this short.

struct LockScreenConditionsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "WeatherWorldLockConditions", provider: WeatherTimelineProvider()
        ) { entry in
            LockScreenConditionsView(entry: entry.snapshot)
                .widgetURL(AppConfig.todayDeepLink)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Conditions")
        .description("Current temperature and conditions.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

private struct LockScreenConditionsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntrySnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            CurrentConditionsContent(entry: entry, layout: .inline)
        case .accessoryRectangular:
            CurrentConditionsContent(entry: entry, layout: .rectangular)
        default:
            CurrentConditionsContent(entry: entry, layout: .circular)
        }
    }
}

struct LockScreenAnomalyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "WeatherWorldLockAnomaly", provider: WeatherTimelineProvider()
        ) { entry in
            LockScreenAnomalyView(entry: entry.snapshot)
                .widgetURL(AppConfig.panelDeepLink(.temperature))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("vs Normal")
        .description("How today compares with the historical average.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

private struct LockScreenAnomalyView: View {
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

struct LockScreenRainWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "WeatherWorldLockRain", provider: WeatherTimelineProvider()
        ) { entry in
            LockScreenRainView(entry: entry.snapshot)
                .widgetURL(AppConfig.panelDeepLink(.rain))
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Rain Chance")
        .description("Today's chance of rain.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

private struct LockScreenRainView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntrySnapshot

    var body: some View {
        switch family {
        case .accessoryInline:
            RainChanceContent(entry: entry, layout: .inline)
        default:
            RainChanceContent(entry: entry, layout: .circular)
        }
    }
}
