import SwiftUI
import WeatherCore

/// Location, condition, big temperature, hi/lo, one anomaly. Units live in the toolbar.
struct NowPage: View {
    let store: WatchStore

    private var atmosphere: Atmosphere.Colors {
        Atmosphere.colors(
            code: store.conditions?.conditionCode,
            isDay: store.conditions?.isDay ?? true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
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
                            .font(.system(size: 42, weight: .semibold, design: .rounded))
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
                            .foregroundStyle(Palette.hot)
                        Text("↓\(store.formatter.temperature(conditions.low))")
                            .foregroundStyle(Palette.cold)
                    }
                    .font(.caption2)

                    badgeOrFallback
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .containerBackground(
            LinearGradient(
                colors: [atmosphere.top, atmosphere.mid, atmosphere.bottom],
                startPoint: .top, endPoint: .bottom).opacity(0.85),
            for: .navigation)
        .navigationTitle("Now")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.imperial.toggle()
                } label: {
                    Text(store.imperial ? "°F" : "°C")
                        .font(.caption2.weight(.semibold))
                }
                .accessibilityLabel("Units")
                .accessibilityHint("Switches between Celsius and Fahrenheit")
            }
        }
    }

    @ViewBuilder
    private var badgeOrFallback: some View {
        if let badge = store.badge {
            Text(badge.text)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Palette.badgeBackground(badge.kind), in: Capsule())
                .foregroundStyle(Palette.badgeForeground(badge.kind))
                .padding(.top, 4)
        } else if !store.hasContext {
            Text("Open the iPhone app for historical context")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}
