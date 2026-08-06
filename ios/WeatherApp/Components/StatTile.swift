import SwiftUI

/// One of the three hero stat tiles (rain chance, wind, UV).
struct StatTile: View {
    let symbol: String
    let tint: Color
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.footnote)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.background.tertiary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

#Preview {
    HStack {
        StatTile(symbol: "drop.fill", tint: .blue, label: "Rain chance", value: "25%")
        StatTile(symbol: "wind", tint: .teal, label: "Wind", value: "20 km/h")
        StatTile(symbol: "sun.max.fill", tint: .orange, label: "UV index", value: "4.1 Moderate")
    }
    .padding()
}
