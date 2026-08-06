import SwiftUI
import WeatherCore

/// The hero card (§8.2 item 2): current temperature, condition, feels-like and
/// hi/lo, the progressive anomaly badges, and three stat tiles.
struct HeroView: View {
    let conditions: CurrentConditions
    let badges: [Anomaly]
    let formatter: UnitFormatter
    let onBadgeTap: (PanelID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    temperature
                    Text(conditions.condition.label)
                        .font(.title3.weight(.medium))
                    range
                    if !badges.isEmpty {
                        badgeRow
                    }
                }
                Spacer(minLength: 12)
                Image(systemName: conditions.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 52))
                    .accessibilityHidden(true)
            }

            statTiles
        }
        .padding(18)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }

    private var temperature: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(formatter.temperatureNumber(conditions.temperature).map(String.init) ?? "—")
                .font(.system(size: 62, weight: .semibold, design: .rounded))
            Text(formatter.temperatureUnit)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Currently \(formatter.temperature(conditions.temperature)), "
                            + conditions.condition.label)
    }

    private var range: some View {
        HStack(spacing: 4) {
            if conditions.feelsLike != nil {
                Text("Feels like \(formatter.temperature(conditions.feelsLike))")
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
            }
            Text("↑\(formatter.temperature(conditions.high))")
                .foregroundStyle(Palette.hot)
            Text("/").foregroundStyle(.tertiary)
            Text("↓\(formatter.temperature(conditions.low))")
                .foregroundStyle(Palette.cold)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private var badgeRow: some View {
        // Badges wrap rather than truncate — some read quite long.
        FlowLayout(spacing: 6) {
            ForEach(badges) { badge in
                AnomalyBadge(anomaly: badge, action: onBadgeTap)
            }
        }
        .padding(.top, 2)
    }

    private var statTiles: some View {
        HStack(spacing: 10) {
            StatTile(
                symbol: "drop.fill", tint: Palette.rainSeries, label: "Rain chance",
                value: formatter.rainChance(conditions.rainChance))
            StatTile(
                symbol: "wind", tint: .teal, label: "Wind",
                value: formatter.wind(conditions.windSpeed))
            StatTile(
                symbol: "sun.max.fill", tint: .orange, label: "UV index",
                value: formatter.uvIndex(conditions.uvIndex))
        }
    }
}

/// Simple wrapping HStack — badge text length varies a lot with units and
/// Dynamic Type, and truncating them would lose the whole point.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let current = rows[rows.count - 1]
            let candidate = current == 0 ? size.width : current + spacing + size.width
            if candidate > maxWidth, current > 0 {
                rows.append(size.width)
                rowHeights.append(size.height)
            } else {
                rows[rows.count - 1] = candidate
                rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
            }
        }
        let height = rowHeights.reduce(0, +) + spacing * CGFloat(max(0, rowHeights.count - 1))
        return CGSize(width: proposal.width ?? rows.max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
