import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Complication content views (§10.1).
///
/// They live in `WeatherCore` so the watchOS extension (Phase 6) and the iOS
/// lock-screen extension (Phase 8) render identically from one definition.
/// Each takes a family so one view can serve every supported size.

// MARK: - Current conditions

public struct CurrentConditionsContent: View {
    public enum Layout { case circular, corner, inline, rectangular }

    let entry: WeatherEntrySnapshot
    let layout: Layout

    public init(entry: WeatherEntrySnapshot, layout: Layout) {
        self.entry = entry
        self.layout = layout
    }

    public var body: some View {
        switch layout {
        case .circular: circular
        case .corner: corner
        case .inline: inline
        case .rectangular: rectangular
        }
    }

    private var circular: some View {
        VStack(spacing: -1) {
            Image(systemName: entry.symbolName)
                .font(.system(size: 13))
            Text(entry.formatter.temperatureShort(entry.temperature))
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.6)
        }
        // Lets a tinted/monochrome watch face or Lock Screen recolor the icon
        // and temperature together, rather than leaving them their fixed color.
        .widgetAccentable()
        .accessibilityLabel(
            "\(entry.formatter.temperature(entry.temperature)), \(entry.condition.label)")
    }

    /// Corner text = temperature; curved bezel label = the next sun event plus
    /// the condition symbol:
    ///
    ///                     32°
    ///             SUNSET 20:58 ⛅
    ///
    /// The temperature is the number you glance at, so it takes the corner's
    /// own (small) area, and the arc carries the rest.
    ///
    /// `accessoryCorner` and `widgetLabel` are watchOS-only; the `#if` keeps the
    /// package compiling on macOS, where the unit tests run.
    private var corner: some View {
        let temperature = Text(entry.formatter.temperatureShort(entry.temperature))
            .font(.title2)
        #if os(watchOS)
        return temperature
            .widgetAccentable()
            .widgetLabel { cornerCurvedLabel.widgetAccentable() }
            .accessibilityLabel(cornerAccessibilityLabel)
        #else
        return temperature.accessibilityLabel(cornerAccessibilityLabel)
        #endif
    }

    /// The curved label, with the condition symbol appended as an inline image.
    var cornerCurvedLabel: Text {
        Text(cornerCurvedText) + Text(" ") + Text(Image(systemName: entry.symbolName))
    }

    /// `"SUNSET 20:58"`. Where the sun never sets or rises — polar summer and
    /// winter — it falls back to today's range rather than showing nothing.
    var cornerCurvedText: String {
        guard let sun = entry.nextSunEvent else {
            return "H\(shortNumber(entry.high)) L\(shortNumber(entry.low))"
        }
        return sun.kind.spokenName.uppercased() + " "
            + sun.formattedTime(timeZone: entry.locationTimeZone)
    }

    private var cornerAccessibilityLabel: String {
        var parts = [
            entry.formatter.temperature(entry.temperature),
            entry.condition.label
        ]
        if let sun = entry.sunEventAccessibilityText { parts.append(sun) }
        return parts.joined(separator: ", ")
    }

    private var inline: some View {
        // accessoryInline renders one line of text with an optional leading image.
        Label {
            Text("\(entry.formatter.temperatureShort(entry.temperature)) "
                 + "H\(shortNumber(entry.high)) L\(shortNumber(entry.low))")
        } icon: {
            Image(systemName: entry.symbolName)
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.locationName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: entry.symbolName)
                    .font(.caption)
                Text(entry.formatter.temperatureShort(entry.temperature))
                    .font(.headline)
                Text(entry.condition.label)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .widgetAccentable()
            Text(secondLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var secondLine: String {
        let range = "H\(shortNumber(entry.high)) L\(shortNumber(entry.low))"
        if let sentence = entry.deltaSentence { return "\(range) · \(sentence)" }
        return range
    }

    private func shortNumber(_ celsius: Double?) -> String {
        entry.formatter.temperatureNumber(celsius).map(String.init) ?? "—"
    }
}

// MARK: - Temperature anomaly (the differentiator)

public struct TempAnomalyContent: View {
    public enum Layout { case circular, inline, rectangular }

    let entry: WeatherEntrySnapshot
    let layout: Layout

    public init(entry: WeatherEntrySnapshot, layout: Layout) {
        self.entry = entry
        self.layout = layout
    }

    public var body: some View {
        // §10.1: with no normals cached there is nothing to say — fall back to
        // current conditions rather than showing an empty dial.
        if entry.temperatureDelta == nil {
            CurrentConditionsContent(entry: entry, layout: fallbackLayout)
        } else {
            switch layout {
            case .circular: circular
            case .inline: inline
            case .rectangular: rectangular
            }
        }
    }

    private var fallbackLayout: CurrentConditionsContent.Layout {
        switch layout {
        case .circular: return .circular
        case .inline: return .inline
        case .rectangular: return .rectangular
        }
    }

    private var circular: some View {
        VStack(spacing: -2) {
            Text(entry.deltaText ?? "≈")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.5)
                .widgetAccentable()
            Text("vs norm")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(entry.deltaSentence ?? "Near normal")
    }

    private var inline: some View {
        Label {
            Text("\(entry.formatter.temperatureShort(entry.temperature)) · "
                 + (entry.deltaSentence ?? "near normal"))
        } icon: {
            Image(systemName: "thermometer.medium")
        }
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: entry.symbolName).font(.caption)
                Text(entry.formatter.temperatureShort(entry.temperature))
                    .font(.headline)
            }
            .widgetAccentable()
            Text(entry.deltaSentence ?? "Near normal")
                .font(.caption2)
                .lineLimit(1)
            Text("H\(entry.formatter.temperatureNumber(entry.high).map(String.init) ?? "—") "
                 + "L\(entry.formatter.temperatureNumber(entry.low).map(String.init) ?? "—")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Rain chance

public struct RainChanceContent: View {
    public enum Layout { case circular, corner, inline }

    let entry: WeatherEntrySnapshot
    let layout: Layout

    public init(entry: WeatherEntrySnapshot, layout: Layout) {
        self.entry = entry
        self.layout = layout
    }

    private var fraction: Double { Double(entry.rainChance ?? 0) / 100 }

    public var body: some View {
        switch layout {
        case .circular:
            Gauge(value: fraction) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text("\(entry.rainChance ?? 0)")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(Gradient(colors: [.gray, .blue]))
            .accessibilityLabel("Rain chance \(entry.rainChance ?? 0) percent")
        case .corner:
            cornerGauge
        case .inline:
            Label {
                Text("Rain \(entry.rainChance ?? 0)%")
            } icon: {
                Image(systemName: "drop.fill")
            }
            .widgetAccentable()
        }
    }

    /// See `CurrentConditionsContent.corner` for why this is platform-gated.
    private var cornerGauge: some View {
        let icon = Image(systemName: "drop.fill")
        #if os(watchOS)
        return icon
            .widgetAccentable()
            .widgetLabel {
                Gauge(value: fraction) {
                    Text("Rain")
                } currentValueLabel: {
                    Text("\(entry.rainChance ?? 0)%")
                }
                .tint(Gradient(colors: [.gray, .blue]))
            }
            .accessibilityLabel("Rain chance \(entry.rainChance ?? 0) percent")
        #else
        return icon
            .accessibilityLabel("Rain chance \(entry.rainChance ?? 0) percent")
        #endif
    }
}
