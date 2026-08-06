import Charts
import SwiftUI
import WeatherCore

/// Shared chart conventions (§8.4): a scrub annotation card replacing the web's
/// DOM tooltip, and the "· actual" / "· forecast" tagging.
enum ChartKit {
    static let hourlyHeight: CGFloat = 170
    static let dailyHeight: CGFloat = 180
    static let ytdHeight: CGFloat = 190
    static let climateTempHeight: CGFloat = 150
    static let climateRainHeight: CGFloat = 90

    /// Dash pattern used for every "forecast" segment.
    static let forecastDash: [CGFloat] = [5, 4]
    /// Dash pattern for historical overlays.
    static let historicalDash: [CGFloat] = [4, 3]
}

/// One row of a scrub annotation.
struct ScrubRow: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
        }
    }
}

/// The floating card shown while scrubbing.
struct ScrubCard<Content: View>: View {
    let title: String
    /// " · actual" / " · forecast", matching the web's tooltip tags.
    let tag: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                Text(title).font(.caption2.weight(.bold))
                if let tag {
                    Text(" · \(tag)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(8)
        .frame(minWidth: 130, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 3, y: 1)
        // Keeps the card from being clipped at the chart's left/right edge.
        .padding(.horizontal, 4)
    }
}

extension ChartContent {
    /// Positions a scrub annotation without letting it run off the plot area.
    func scrubAnnotation<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some ChartContent {
        // Constrained on both axes: with `y: .disabled` the card floated above
        // the plot and covered the section title.
        annotation(
            position: .top,
            spacing: 2,
            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
        ) {
            content()
        }
    }
}

/// Hour label matching the web's `_hourLbl`: "Midnight", "Noon", "3am", "5pm".
func hourLabel(_ hour: Int) -> String {
    switch hour {
    case 0: return "Midnight"
    case 12: return "Noon"
    case ..<12: return "\(hour)am"
    default: return "\(hour - 12)pm"
    }
}

extension Date {
    func formatted(_ style: Date.FormatStyle, in timeZone: TimeZone) -> String {
        var copy = style
        copy.timeZone = timeZone
        return formatted(copy)
    }
}
