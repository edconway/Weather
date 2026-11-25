import SwiftUI
import WeatherCore

/// The hinge and the cameras, read from the view they overlap.
///
/// `GeometryProxy.reservedRegions(kind:options:)` is the iOS 27.1 query.
/// `.division` with `.includeInactive` is the fold: the cover reports none,
/// and the inner display reports one. That region's `isActive` is false while
/// the glass is flat and true in book and tent. `.occlusion` is the camera
/// and the status column; only the active ones are read, so the inner camera
/// is ignored until it turns on. The frame already includes the margins.
enum DuoFold {
    struct Reading: Equatable {
        var division: DuoDivision?
        /// True when the division region is active and content must stay out of it.
        var hingeSeparates = false
        var occlusions: [DuoDivision] = []
    }

    static func reading(in proxy: GeometryProxy) -> Reading {
        #if targetEnvironment(macCatalyst)
        _ = proxy.size
        return Reading()
        #else
        let divisions = proxy.reservedRegions(kind: .division, options: .includeInactive)
        let occlusions = proxy.reservedRegions(kind: .occlusion).map { rect($0.frame) }
        guard let hinge = divisions.max(by: { area($0.frame) < area($1.frame) }) else {
            return Reading(occlusions: occlusions)
        }
        let frame = hinge.frame
        guard frame.width > 1, frame.height > 1 else {
            return Reading(occlusions: occlusions)
        }
        return Reading(
            division: rect(frame),
            hingeSeparates: hinge.isActive,
            occlusions: occlusions)
        #endif
    }

    /// The inner-display hinge, or nil on the cover and on a phone with no fold.
    /// Flat and folded inner displays both return the hinge, so this is nil only
    /// when the system reports no division.
    static func active(in proxy: GeometryProxy) -> DuoDivision? {
        reading(in: proxy).division
    }

    #if !targetEnvironment(macCatalyst)
    private static func area(_ frame: CGRect) -> CGFloat {
        frame.width * frame.height
    }

    private static func rect(_ frame: CGRect) -> DuoDivision {
        DuoDivision(
            x: Double(frame.origin.x),
            y: Double(frame.origin.y),
            width: Double(frame.size.width),
            height: Double(frame.size.height))
    }
    #endif
}

struct DuoMetrics: Equatable {
    var size: CGSize = .zero
    var fold: DuoDivision?
    var hingeSeparates = false
    var occlusion = DuoPadding.zero
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

    func duoPadding(_ insets: DuoPadding) -> some View {
        padding(EdgeInsets(
            top: CGFloat(insets.top),
            leading: CGFloat(insets.leading),
            bottom: CGFloat(insets.bottom),
            trailing: CGFloat(insets.trailing)))
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
