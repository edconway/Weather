import SwiftUI
import WeatherCore

/// §9.1 — location, condition, big temperature, hi/lo, feels-like, a glyph row,
/// and the single highest-priority anomaly badge.
struct NowPage: View {
    let store: WatchStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                if let name = store.location?.shortName, !name.isEmpty {
                    Text(name)
                        .id(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let conditions = store.conditions {
                    let tint = temperatureColor(conditions.temperature)
                    HStack(alignment: .center, spacing: 4) {
                        Text(degree(conditions.temperature))
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: conditions.symbolName)
                            .symbolRenderingMode(.monochrome)
                            .font(.title3)
                            .foregroundStyle(tint)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(store.formatter.temperature(conditions.temperature)), "
                        + conditions.condition.label)

                    Text(conditions.condition.label)
                        .font(.caption)
                        .lineLimit(1)

                    Text(rangeLine(conditions))
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if let gauge = store.todayGauge {
                        TemperatureRangeGauge(
                            data: gauge,
                            style: .widget,
                            unit: store.imperial ? .fahrenheit : .celsius,
                            weatherBackground: Color(red: 0.05, green: 0.12, blue: 0.28),
                            seed: TemperatureGaugeSeed(
                                locationID: store.location?.cacheKey ?? "",
                                day: conditions.todayString))
                    }

                    if conditions.feelsLike != nil {
                        Text("Feels \(store.formatter.temperatureShort(conditions.feelsLike))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    statGlyphs(conditions)
                    badgeOrFallback(temperature: conditions.temperature)
                    unitsToggle
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.blue.gradient.opacity(0.25), for: .navigation)
        .navigationTitle("Now")
    }

    private func degree(_ celsius: Double) -> String {
        guard let number = store.formatter.temperatureNumber(celsius) else { return "—" }
        return "\(number)°"
    }

    private func temperatureColor(_ celsius: Double) -> Color {
        let rgb = TemperatureColorScale.color(celsius: celsius)
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// Today's low–high, then the usual range when the phone has sent it.
    private func rangeLine(_ conditions: CurrentConditions) -> String {
        let today = span(conditions.low, conditions.high)
        guard let gauge = store.todayGauge,
              let usual = span(gauge.averageLow, gauge.averageHigh) else { return today }
        return "\(today) · usual \(usual)"
    }

    private func span(_ low: Double?, _ high: Double?) -> String {
        guard let low, let high,
              let a = store.formatter.temperatureNumber(low),
              let b = store.formatter.temperatureNumber(high) else { return "—" }
        return "\(a)–\(b)°"
    }

    private func statGlyphs(_ conditions: CurrentConditions) -> some View {
        HStack(spacing: 8) {
            Label(
                store.formatter.rainChance(conditions.rainChance),
                systemImage: "drop.fill")
            Label(
                store.formatter.wind(conditions.windSpeed),
                systemImage: "wind")
            Label(
                store.formatter.uvIndexCompact(conditions.uvIndex),
                systemImage: "sun.max.fill")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func badgeOrFallback(temperature: Double) -> some View {
        if let badge = store.badge {
            Text(badge.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(badgeColor(badge.kind, temperature: temperature))
                .lineLimit(2)
                .padding(.top, 2)
                .accessibilityLabel(badge.text)
        } else if !store.hasContext {
            // Climate normals still need the phone; recent-day badges cover most
            // cases without it. This only shows when even that is unavailable.
            Text("Open iPhone for climate normals")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 4)
        }
    }

    /// §9 asked for a local imperial/metric toggle alongside the phone-synced
    /// default. `WatchStore.imperial` is `@Observable` and persists via its own
    /// `didSet`, so this button only needs to flip it.
    ///
    /// Note: the next phone sync overwrites this choice
    /// (`applySyncedPayload` sets `imperial = payload.imperial`), matching the
    /// plan's "units synced from phone prefs, plus local toggle" — the local
    /// toggle is an override until the next sync, not a permanent split.
    private var unitsToggle: some View {
        Button {
            store.imperial.toggle()
        } label: {
            Text(store.imperial ? "Switch to °C" : "Switch to °F")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
        .accessibilityHint("Changes temperature and wind units")
    }

    private func badgeColor(_ kind: AnomalyKind, temperature: Double) -> Color {
        switch kind {
        case .warm: return temperatureColor(temperature)
        case .cold: return temperatureColor(min(temperature, 8))
        default: return badgeTint(kind)
        }
    }

    private func badgeTint(_ kind: AnomalyKind) -> Color {
        switch kind {
        case .warm: return .orange
        case .cold: return .blue
        case .wet: return .teal
        case .dry: return .gray
        case .muggy: return .purple
        case .muggyLow: return .mint
        case .neutral: return .secondary
        }
    }
}
