import SwiftUI
import WeatherCore

/// A coloured panel with a cap and one or more chart sections, mirroring the
/// web's `.weather-panel` / `.panel-cap` / `.sec-hdr` structure (§8.2).
struct PanelCard<Content: View>: View {
    let id: PanelID
    let symbol: String
    let title: String
    let hint: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cap
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(16)
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
        .id(id)
    }

    private var cap: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.bold))
            Text(hint)
                .font(.caption)
                .opacity(0.85)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(tint.opacity(0.16)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The `secHdr(title, details)` header above each chart.
struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
