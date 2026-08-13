import SwiftUI

/// Compact chart container: eyebrow, subtitle, one-line readout, plot.
///
/// The readout is the scrub target — dragging a chart rewrites it instead of
/// floating a tooltip over the plot. Large Health-style numbers are gone so
/// the plot (the original DNA) gets the space.
struct ChartModule<Chart: View, Detail: View>: View {
    let eyebrow: String
    let readout: ChartReadout
    let detailText: String?
    let legend: [ChartLegendItem]
    var onOpenDetail: (() -> Void)? = nil
    @ViewBuilder var chart: () -> Chart
    @ViewBuilder var detail: () -> Detail

    init(
        eyebrow: String,
        readout: ChartReadout,
        detailText: String? = nil,
        legend: [ChartLegendItem] = [],
        onOpenDetail: (() -> Void)? = nil,
        @ViewBuilder chart: @escaping () -> Chart,
        @ViewBuilder detail: @escaping () -> Detail = { EmptyView() }
    ) {
        self.eyebrow = eyebrow
        self.readout = readout
        self.detailText = detailText
        self.legend = legend
        self.onOpenDetail = onOpenDetail
        self.chart = chart
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                if let detailText, !detailText.isEmpty {
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }

                readoutHeader
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onOpenDetail?() }
            .accessibilityAddTraits(onOpenDetail == nil ? [] : .isButton)
            .accessibilityHint(onOpenDetail == nil ? "" : "Shows a larger chart")

            chart()
                .chartAppear()

            if !legend.isEmpty {
                ChartLegendRow(items: legend)
            }

            detail()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(eyebrow)
        .accessibilityValue("\(readout.primary). \(readout.context)")
    }

    private var readoutHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(readout.primary)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(readout.primaryTint ?? .primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(readout.context)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if onOpenDetail != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChartReadout: Equatable {
    var primary: String
    var context: String
    var primaryTint: Color? = nil

    static let placeholder = ChartReadout(primary: "—", context: "")
}

struct ChartLegendItem: Identifiable, Equatable {
    enum Swatch: Equatable {
        case solid(Color)
        case dashed(Color)
        case band(Color)
    }

    let id: String
    let label: String
    let swatch: Swatch

    init(_ label: String, swatch: Swatch) {
        self.id = label
        self.label = label
        self.swatch = swatch
    }
}

struct ChartLegendRow: View {
    let items: [ChartLegendItem]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items) { item in
                HStack(spacing: 5) {
                    swatchView(item.swatch)
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map(\.label).joined(separator: ", "))
    }

    @ViewBuilder
    private func swatchView(_ swatch: ChartLegendItem.Swatch) -> some View {
        switch swatch {
        case .solid(let color):
            Capsule()
                .fill(color)
                .frame(width: 14, height: 3)
        case .dashed(let color):
            Capsule()
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 14, height: 3)
        case .band(let color):
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 8)
        }
    }
}
