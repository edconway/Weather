import SwiftUI

/// Keeps the last `chartXSelection` value after the gesture ends.
///
/// PLAN DEVIATION §1.4.6: the plan maps the web's tooltip onto
/// `chartXSelection`, but that binding resets to `nil` the moment the finger
/// lifts, so on a touch screen the annotation flashes and vanishes. The web
/// tooltip is driven by `mousemove` and stays put while the pointer is over the
/// chart, so persisting the last selection is the closer equivalent — and it is
/// the only version a screenshot can verify.
struct StickyXSelection<Value: Equatable, ResetKey: Equatable>: ViewModifier {
    @Binding var live: Value?
    @Binding var sticky: Value?
    /// Identifies the data behind the chart. When it changes the selection is
    /// dropped — otherwise switching location leaves the old scrub card in
    /// place, relabelled with the new location's numbers.
    let resetKey: ResetKey

    func body(content: Content) -> some View {
        content
            .onChange(of: live) { _, newValue in
                // Ignore the reset-to-nil at gesture end; adopt every real value.
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
