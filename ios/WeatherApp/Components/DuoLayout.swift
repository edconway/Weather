import SwiftUI

/// Layout for a resizable iPhone, including iPhone Duo.
///
/// This SDK has no Duo idiom and no inner-display pose. The outer display is a
/// compact width, like any other iPhone. The inner display is a regular width.
/// A split is used only when that regular width can actually hold two columns.
enum StatusCanvas {
    /// Narrowest pair of columns that still leaves the status and the charts readable.
    static let splitMinimum: CGFloat = 600
    static let statusMaximum: CGFloat = 420
    static let chartPairMinimum: CGFloat = 640

    static func prefersSplit(horizontal: UserInterfaceSizeClass?, width: CGFloat) -> Bool {
        horizontal == .regular && width >= splitMinimum
    }

    static func statusWidth(in width: CGFloat) -> CGFloat {
        min(statusMaximum, max(300, width * 0.4))
    }
}

private struct CanvasWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Reports the width actually offered to this view, including after a fold.
struct CanvasWidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { geo in
            Color.clear.preference(key: CanvasWidthKey.self, value: geo.size.width)
        }
        .onPreferenceChange(CanvasWidthKey.self) { width = $0 }
    }
}

extension View {
    /// Centers sheet content on a regular-width canvas so a form does not stretch
    /// across the unfolded display.
    func readableWhenRegular() -> some View {
        modifier(ReadableWhenRegular())
    }
}

private struct ReadableWhenRegular: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: horizontalSizeClass == .regular ? 640 : .infinity)
            .frame(maxWidth: .infinity)
    }
}
