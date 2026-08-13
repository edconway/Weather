import SwiftUI
import WeatherCore

/// Compact atmospheric hero: temperature, date, equal anomaly badges, stats strip.
struct HeroView: View {
    let conditions: CurrentConditions
    let badges: [Anomaly]
    let formatter: UnitFormatter
    var dateLine: String = ""
    let onBadgeTap: (PanelID) -> Void

    private var atmosphere: Atmosphere.Colors {
        Atmosphere.colors(code: conditions.conditionCode, isDay: conditions.isDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if !dateLine.isEmpty {
                        Text(dateLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(atmosphere.secondaryForeground)
                    }
                    temperature
                    Text(conditions.condition.label)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(atmosphere.foreground)
                    range
                }
                Spacer(minLength: 12)
                Image(systemName: conditions.symbolName)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 52))
                    .foregroundStyle(atmosphere.foreground.opacity(0.92))
                    .accessibilityHidden(true)
            }

            if !badges.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(badges) { badge in
                        AnomalyBadge(anomaly: badge, action: onBadgeTap)
                    }
                }
            }

            materialStrip
        }
        .padding(.horizontal, 20)
        .padding(.top, 88)
        .padding(.bottom, 18)
        .foregroundStyle(atmosphere.foreground)
        .background {
            AtmosphereBackground(colors: atmosphere, compact: true)
        }
    }

    private var temperature: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(formatter.temperatureNumber(conditions.temperature).map(String.init) ?? "—")
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(formatter.temperatureUnit)
                .font(.title2.weight(.medium))
                .foregroundStyle(atmosphere.secondaryForeground)
                .padding(.top, 10)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Currently \(formatter.temperature(conditions.temperature)), "
                            + conditions.condition.label)
    }

    private var range: some View {
        HStack(spacing: 4) {
            if conditions.feelsLike != nil {
                Text("Feels \(formatter.temperature(conditions.feelsLike))")
                    .foregroundStyle(atmosphere.secondaryForeground)
                Text("·").opacity(0.55)
            }
            Text("H \(formatter.temperature(conditions.high))")
                .foregroundStyle(Palette.hot)
            Text("/").opacity(0.55)
            Text("L \(formatter.temperature(conditions.low))")
                .foregroundStyle(Palette.cold)
        }
        .font(.subheadline.weight(.medium))
        .accessibilityElement(children: .combine)
    }

    private var materialStrip: some View {
        HStack(spacing: 0) {
            stripItem(
                symbol: "drop.fill",
                label: "Rain",
                value: formatter.rainChance(conditions.rainChance))
            stripDivider
            stripItem(
                symbol: "wind",
                label: "Wind",
                value: formatter.wind(conditions.windSpeed))
            stripDivider
            stripItem(
                symbol: "sun.max.fill",
                label: "UV",
                value: formatter.uvIndexCompact(conditions.uvIndex))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func stripItem(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .opacity(0.75)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(.primary.opacity(0.12))
            .frame(width: 1, height: 28)
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
