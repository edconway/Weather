import SwiftUI
import WeatherCore

/// Day or night sky, the anomaly line, today's range against normal, and rain / wind / UV.
struct HeroView: View {
    let placeName: String
    let showsGPS: Bool
    let conditions: CurrentConditions
    let voice: ScreenPresentation.HeroVoice?
    let range: ScreenPresentation.TodayRange?
    let outlook: ScreenPresentation.RainOutlook
    let topInset: CGFloat
    let formatter: UnitFormatter
    let onSearch: () -> Void
    let onSettings: () -> Void
    let onVoice: (PanelID) -> Void

    private var atmosphere: Atmosphere.Colors {
        Atmosphere.colors(code: conditions.conditionCode, isDay: conditions.isDay)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chrome
            temperatureRow
            conditionLine
            voiceButton
            TodayRangeBar(range: range, formatter: formatter, ink: atmosphere.foreground, dim: atmosphere.secondaryForeground)
            stats
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset + 8)
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(atmosphere.foreground)
        .background { AtmosphereBackground(colors: atmosphere) }
    }

    private var chrome: some View {
        HStack {
            Button(action: onSearch) {
                HStack(spacing: 6) {
                    Image(systemName: showsGPS ? "location.fill" : "mappin")
                        .font(.caption.weight(.semibold))
                    Text(placeName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .opacity(0.8)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Location: \(placeName)")
            .accessibilityHint("Search for a different location")

            Spacer(minLength: 8)

            Button(action: onSettings) {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var temperatureRow: some View {
        HStack(alignment: .top) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(formatter.temperatureNumber(conditions.temperature).map(String.init) ?? "—")
                    .font(.system(size: 76, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(formatter.temperatureUnit)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(atmosphere.secondaryForeground)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Currently \(formatter.temperature(conditions.temperature)), "
                                + conditions.condition.label)
            Spacer(minLength: 12)
            Image(systemName: conditions.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 56))
                .foregroundStyle(atmosphere.foreground.opacity(0.95))
                .accessibilityHidden(true)
        }
        .padding(.top, 8)
    }

    private var conditionLine: some View {
        let feels = conditions.feelsLike.map { " · feels \(formatter.temperatureShort($0))" } ?? ""
        return Text(conditions.condition.label + feels)
            .font(.title3.weight(.semibold))
            .padding(.top, 8)
    }

    private var voiceButton: some View {
        Group {
            if let voice {
                Button {
                    onVoice(voice.panel)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(voice.headline)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Text(voice.detail)
                            .font(.subheadline)
                            .foregroundStyle(atmosphere.secondaryForeground)
                            .multilineTextAlignment(.leading)
                            .frame(minHeight: 18, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the \(Self.panelName(voice.panel)) section")
            } else {
                Color.clear.frame(height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, 10)
        .frame(minHeight: 48, alignment: .topLeading)
    }

    private static func panelName(_ panel: PanelID) -> String {
        switch panel {
        case .temperature: return "temperature"
        case .wetBulb: return "wet bulb"
        case .rain: return "rain"
        case .climate: return "climate"
        }
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 8) {
            stat("Rain", outlook.heroValue)
            stat("Wind", formatter.wind(conditions.windSpeed))
            stat(conditions.isDay ? "UV" : "UV peak", formatter.uvIndexCompact(conditions.uvIndex))
        }
        .padding(.top, 28)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(atmosphere.secondaryForeground)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

struct TodayRangeBar: View {
    let range: ScreenPresentation.TodayRange?
    let formatter: UnitFormatter
    let ink: Color
    let dim: Color

    var body: some View {
        Group {
            if let range {
                filled(range)
            } else {
                Color.clear
            }
        }
        .frame(height: 92)
        .padding(.top, 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(range.map { value in
            "Today \(formatter.temperatureShort(value.low)) to \(formatter.temperatureShort(value.high)). "
                + "Normal \(formatter.temperatureShort(value.normalLow)) to \(formatter.temperatureShort(value.normalHigh))."
        } ?? "Normal range unavailable")
    }

    private func filled(_ range: ScreenPresentation.TodayRange) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: width * range.normalWidth, height: 16)
                    .offset(x: width * range.normalStart, y: 6)
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(width * range.todayWidth, 4), height: 6)
                    .offset(x: width * range.todayStart, y: 11)
                if let now = range.nowFraction {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Color.black.opacity(0.45), lineWidth: 2.5))
                        .offset(x: width * now - 6.5, y: 7)
                }
                label(formatter.temperatureShort(range.low), at: range.lowLabelFraction, width: width, color: ink)
                label(formatter.temperatureShort(range.high), at: range.highLabelFraction, width: width, color: ink)
                Text("normal \(formatter.temperatureShort(range.normalLow))–\(formatter.temperatureShort(range.normalHigh))")
                    .font(.caption)
                    .foregroundStyle(dim)
                    .fixedSize()
                    .position(x: width * range.captionFraction, y: 74)
            }
        }
    }

    private func label(_ text: String, at fraction: Double, width: CGFloat, color: Color) -> some View {
        Text(text)
            .font(.footnote.weight(.bold))
            .foregroundStyle(color)
            .fixedSize()
            .position(x: width * fraction, y: 48)
    }
}
