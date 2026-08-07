import SwiftUI

/// Coordinates chart tooltips across a screen so only one is ever pinned at a
/// time. `TodayScreen` owns one instance and injects it via `.environment(_:)`;
/// every `StickyXSelection` on that screen shares it, so scrubbing a new chart
/// clears whichever chart's card was showing before — without this, each
/// chart's sticky selection is independent and old cards are left stuck on
/// screen indefinitely.
@Observable
final class ActiveScrubCoordinator {
    var activeID: AnyHashable?
}

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
    /// This chart's identity in `ActiveScrubCoordinator` — scrubbing any other
    /// chart clears this one.
    let id: AnyHashable

    @Environment(ActiveScrubCoordinator.self) private var coordinator

    func body(content: Content) -> some View {
        content
            .onChange(of: live) { _, newValue in
                // Ignore the reset-to-nil at gesture end; adopt every real value.
                if let newValue {
                    sticky = newValue
                    coordinator.activeID = id
                }
            }
            .onChange(of: resetKey) { _, _ in
                live = nil
                sticky = nil
            }
            .onChange(of: coordinator.activeID) { _, activeID in
                guard sticky != nil, activeID != id else { return }
                live = nil
                sticky = nil
            }
    }
}

extension View {
    func stickyXSelection<Value: Equatable, ResetKey: Equatable>(
        id: AnyHashable, live: Binding<Value?>, sticky: Binding<Value?>, resetOn resetKey: ResetKey
    ) -> some View {
        modifier(StickyXSelection(live: live, sticky: sticky, resetKey: resetKey, id: id))
    }
}
