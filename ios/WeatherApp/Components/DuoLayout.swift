import SwiftUI
import WeatherCore

/// The hinge, when this SDK can see it.
///
/// iPhone Duo (November 2026) describes the fold as a division reserved region
/// and the cameras as occlusion regions. `GeometryProxy` in this SDK has
/// neither `reservedRegions` nor a Duo idiom. The page therefore cannot tell
/// a book or a tent from a flat display, and it cannot see the inner camera
/// turn on. Cover and the open inner display both use the one-column layout,
/// inset by the safe area so a side toolbar or Split View does not cover it.
enum DuoFold {
    static func active(in proxy: GeometryProxy) -> DuoDivision? {
        _ = proxy.size
        return nil
    }
}

struct DuoMetrics: Equatable {
    var size: CGSize = .zero
    var fold: DuoDivision?
}

struct DuoMetricsKey: PreferenceKey {
    static var defaultValue = DuoMetrics()
    static func reduce(value: inout DuoMetrics, nextValue: () -> DuoMetrics) {
        value = nextValue()
    }
}

extension View {
    /// Keeps a sheet from stretching across the unfolded inner display.
    func readableWhenRegular() -> some View {
        modifier(ReadableWhenRegular())
    }
}

private struct ReadableWhenRegular: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: horizontalSizeClass == .regular ? 680 : .infinity)
            .frame(maxWidth: .infinity)
    }
}
