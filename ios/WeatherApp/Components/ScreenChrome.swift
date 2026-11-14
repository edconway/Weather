import SwiftUI
import UIKit
import WeatherCore

struct HeroBottomPreference: PreferenceKey {
    static var defaultValue: CGFloat = .greatestFiniteMagnitude
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}

struct WindowTopInset: UIViewControllerRepresentable {
    @Binding var top: CGFloat

    func makeUIViewController(context: Context) -> InsetController {
        let controller = InsetController()
        controller.onInset = { inset in
            if inset > 0, inset != top { top = inset }
        }
        return controller
    }

    func updateUIViewController(_ controller: InsetController, context: Context) {
        controller.onInset = { inset in
            if inset > 0, inset != top { top = inset }
        }
        controller.report()
    }

    final class InsetController: UIViewController {
        var onInset: ((CGFloat) -> Void)?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            report()
        }

        func report() {
            let inset = view.window?.safeAreaInsets.top ?? 0
            guard inset > 0 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onInset?(inset)
            }
        }
    }
}

struct SectionTopsPreference: PreferenceKey {
    static var defaultValue: [PanelID: CGFloat] = [:]
    static func reduce(value: inout [PanelID: CGFloat], nextValue: () -> [PanelID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Temp / Wet bulb / Rain / Climate. The same control sits in the sheet and in the pinned header.
struct SectionSegmentBar: View {
    let selected: PanelID
    let onSelect: (PanelID) -> Void

    private let panels: [(PanelID, String)] = [
        (.temperature, "Temp"),
        (.wetBulb, "Wet bulb"),
        (.rain, "Rain"),
        (.climate, "Climate")
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(panels, id: \.0) { panel, title in
                Button {
                    onSelect(panel)
                } label: {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selected == panel ? Color(.systemBackground) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .foregroundStyle(selected == panel ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == panel ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Jump to section")
    }
}

/// Fades in once the hero has scrolled away. Place, conditions, and the section bar.
struct PinnedHeader: View {
    let placeName: String
    let showsGPS: Bool
    let nowLine: String
    let updated: String
    let selected: PanelID
    let onPlace: () -> Void
    let onSelect: (PanelID) -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onPlace) {
                HStack(spacing: 8) {
                    Image(systemName: showsGPS ? "location.fill" : "mappin")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(placeName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(nowLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(updated)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(placeName), \(nowLine), \(updated)")
            SectionSegmentBar(selected: selected, onSelect: onSelect)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
}

/// Open-Meteo hourly rain sentence. Larger and tinted when rain is happening or due within three hours.
struct OutlookCard: View {
    let outlook: ScreenPresentation.RainOutlook

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "umbrella.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.rainSeries)
                .frame(width: 36, height: 36)
                .background(Palette.rainSeries.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(outlook.headline)
                    .font(outlook.prominent ? .title3.weight(.semibold) : .body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = outlook.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(outlook.sourceCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ChanceSpark(chances: outlook.hourlyChance)
        }
        .padding(outlook.prominent ? 16 : 12)
        .background(
            outlook.prominent ? Palette.rainSeries.opacity(0.12) : Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if outlook.prominent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.rainSeries.opacity(0.45), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct ChanceSpark: View {
    let chances: [Int]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(chances.prefix(12).enumerated()), id: \.offset) { _, chance in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Palette.rainSeries.opacity(0.85))
                    .frame(width: 3, height: max(2, CGFloat(chance) / 100 * 26))
            }
        }
        .frame(width: 62, height: 26, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

struct RainTotalsRow: View {
    let totals: ScreenPresentation.RainWindowTotals
    let formatter: UnitFormatter

    var body: some View {
        HStack(spacing: 8) {
            tile("Last 7 days", totals.last7, totals.lastNormal)
            tile("Next 7 days", totals.next7, totals.nextNormal)
        }
    }

    private func tile(_ title: String, _ amount: Double, _ normal: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(formatter.precipitation(amount))
                .font(.title3.weight(.bold))
            Text(foot(amount, normal))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func foot(_ amount: Double, _ normal: Double?) -> String {
        guard let normal else { return " " }
        if normal < 1 { return "normally dry" }
        let pct = Int((amount / normal * 100).rounded())
        return "\(pct)% of normal"
    }
}

/// Replaces the wet-bulb charts while the week's peak stays under 15°C.
struct WetBulbCollapsedCard: View {
    let now: String
    let detail: String
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Wet bulb \(now) · no heat stress")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
