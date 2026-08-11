import SwiftUI
import WeatherCore

/// A tappable hero badge. Tapping scrolls to the badge's panel, mirroring the
/// web's `data-panel-jump` (§6.8).
struct AnomalyBadge: View {
    let anomaly: Anomaly
    let action: (PanelID) -> Void

    var body: some View {
        Button {
            action(anomaly.panel)
        } label: {
            Text(anomaly.text)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Palette.badgeBackground(anomaly.kind), in: Capsule())
                .foregroundStyle(Palette.badgeForeground(anomaly.kind))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(anomaly.text)
        .accessibilityHint(Self.hint(for: anomaly))
    }

    static func hint(for anomaly: Anomaly) -> String {
        switch anomaly.panel {
        case .temperature: return "Shows the temperature panel"
        case .wetBulb: return "Shows the wet bulb panel"
        case .rain: return "Shows the rain panel"
        case .climate: return "Shows the climate overview panel"
        }
    }
}

#Preview {
    VStack(alignment: .leading) {
        AnomalyBadge(
            anomaly: Anomaly(text: "3°C warmer than normal", kind: .warm, panel: .temperature),
            action: { _ in })
        AnomalyBadge(
            anomaly: Anomaly(text: "Feels 25% more muggy than usual", kind: .muggy, panel: .wetBulb),
            action: { _ in })
        AnomalyBadge(
            anomaly: Anomaly(text: "Near normal rainfall", kind: .neutral, panel: .rain),
            action: { _ in })
    }
    .padding()
}
