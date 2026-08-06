import SwiftUI
import WeatherCore
import WidgetKit

/// Phase 8 — the iOS home-screen widget. Lock-screen accessories reuse the
/// shared §10 views; these two sizes are iOS-only, so they live here.
struct HeroWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeatherWorldHero", provider: WeatherTimelineProvider()) { entry in
            HeroWidgetView(entry: entry.snapshot)
                .widgetURL(AppConfig.todayDeepLink)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weather World")
        .description("Current conditions with historical context.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct HeroWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntrySnapshot

    var body: some View {
        switch family {
        case .systemMedium: medium
        default: small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.locationName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: entry.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.caption)
            }
            Text(entry.formatter.temperatureShort(entry.temperature))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
            Text(entry.condition.label)
                .font(.caption2)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let sentence = entry.deltaSentence {
                Text(sentence)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(deltaTint)
                    .lineLimit(2)
            } else {
                Text(range)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small
            VStack(alignment: .leading, spacing: 6) {
                stat("Hi / Lo", range)
                stat("Rain", entry.formatter.rainChance(entry.rainChance))
                if let sun = entry.nextSunEvent {
                    stat(
                        sun.kind == .sunrise ? "Sunrise" : "Sunset",
                        sun.formattedTime(timeZone: entry.locationTimeZone))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.medium))
        }
    }

    private var range: String {
        "H\(entry.formatter.temperatureNumber(entry.high).map(String.init) ?? "—") "
        + "L\(entry.formatter.temperatureNumber(entry.low).map(String.init) ?? "—")"
    }

    private var deltaTint: Color {
        guard let delta = entry.temperatureDelta else { return .secondary }
        if abs(delta) < 1 { return .secondary }
        return delta > 0 ? .orange : .blue
    }
}
