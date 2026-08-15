import SwiftUI
import WeatherCore

/// §9.1 — location, condition, big temperature, hi/lo, feels-like, a glyph row,
/// and the single highest-priority anomaly badge.
struct NowPage: View {
    let store: WatchStore

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let name = store.location?.shortName, !name.isEmpty {
                Text(name)
                    .id(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let conditions = store.conditions {
                HStack(alignment: .top, spacing: 6) {
                    Text(store.formatter.temperatureNumber(conditions.temperature)
                            .map(String.init) ?? "—")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                    Text(store.formatter.temperatureUnit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                    Image(systemName: conditions.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.title3)
                        .padding(.top, 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(store.formatter.temperature(conditions.temperature)), "
                    + conditions.condition.label)

                Text(conditions.condition.label)
                    .font(.caption)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("↑\(store.formatter.temperature(conditions.high))")
                        .foregroundStyle(.orange)
                    Text("↓\(store.formatter.temperature(conditions.low))")
                        .foregroundStyle(.blue)
                }
                .font(.caption2)

                if conditions.feelsLike != nil {
                    Text("Feels \(store.formatter.temperature(conditions.feelsLike))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                statGlyphs(conditions)
                badgeOrFallback
                unitsToggle
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.blue.gradient.opacity(0.25), for: .navigation)
        .navigationTitle("Now")
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
    private var badgeOrFallback: some View {
        if let badge = store.badge {
            Text(badge.text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(badgeTint(badge.kind).opacity(0.22), in: Capsule())
                .foregroundStyle(badgeTint(badge.kind))
                .padding(.top, 4)
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
