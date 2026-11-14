import SwiftUI
import WeatherCore

/// Apple's required Weather attribution: the combined mark, and the legal page when it can be opened.
struct AppleAttributionView: View {
    let attribution: AppleWeatherAttribution

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            mark
            if let legalPageURL = attribution.legalPageURL {
                Link("Weather legal attribution", destination: legalPageURL)
                    .font(.caption2)
            } else if let legalAttributionText = attribution.legalAttributionText, !legalAttributionText.isEmpty {
                Text(legalAttributionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(attribution.serviceName)
    }

    @ViewBuilder
    private var mark: some View {
        let url = colorScheme == .dark ? attribution.markDarkURL : attribution.markLightURL
        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Text(attribution.serviceName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 16)
            .frame(maxWidth: 140, alignment: .leading)
        } else {
            Text(attribution.serviceName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
