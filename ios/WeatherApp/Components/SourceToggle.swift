import SwiftUI
import WeatherCore

/// The two-location capsule (§8.2 item 1), shown only when both a GPS fix and a
/// searched location exist — a port of the web's `src-toggle` logic.
struct SourceToggle: View {
    let activeSource: WeatherLocation.Source
    let customShortName: String
    let onSelect: (WeatherLocation.Source) -> Void

    var body: some View {
        HStack(spacing: 4) {
            button(.geo, symbol: "location.fill", title: "My Location")
            button(.custom, symbol: "building.2.fill", title: customShortName)
        }
        .padding(3)
        .background(.background.tertiary, in: Capsule())
    }

    private func button(
        _ source: WeatherLocation.Source, symbol: String, title: String
    ) -> some View {
        let isActive = source == activeSource
        return Button {
            onSelect(source)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2)
                Text(title).font(.caption.weight(isActive ? .semibold : .regular))
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? AnyShapeStyle(Palette.accent.opacity(0.18)) : AnyShapeStyle(.clear),
                        in: Capsule())
            .foregroundStyle(isActive ? Palette.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    SourceToggle(activeSource: .geo, customShortName: "Paris", onSelect: { _ in })
        .padding()
}
