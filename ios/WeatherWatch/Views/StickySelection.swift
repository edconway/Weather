import SwiftUI

/// Watch-local copy of the iOS app's `StickyXSelection` (`WeatherApp/Charts/StickySelection.swift`,
/// which lives in the iOS target and isn't reachable from here).
///
/// `chartXSelection` resets to `nil` the instant a tap/drag ends, so without
/// this the scrub card would flash and vanish before it could be read — worse
/// on a watch, where the gesture is a stubby finger on a 40mm screen.
struct StickyXSelection<Value: Equatable, ResetKey: Equatable>: ViewModifier {
    @Binding var live: Value?
    @Binding var sticky: Value?
    /// Identifies the data behind the chart; the selection drops when it
    /// changes, so switching location can't leave a stale card on screen.
    let resetKey: ResetKey

    func body(content: Content) -> some View {
        content
            .onChange(of: live) { _, newValue in
                if let newValue { sticky = newValue }
            }
            .onChange(of: resetKey) { _, _ in
                live = nil
                sticky = nil
            }
    }
}

extension View {
    func stickyXSelection<Value: Equatable, ResetKey: Equatable>(
        live: Binding<Value?>, sticky: Binding<Value?>, resetOn resetKey: ResetKey
    ) -> some View {
        modifier(StickyXSelection(live: live, sticky: sticky, resetKey: resetKey))
    }
}
