import SwiftUI
import WeatherCore
import WidgetKit

@main
struct WeatherWatchApp: App {
    @State private var store = WatchStore()
    @State private var session: WatchSessionManager?

    var body: some Scene {
        WindowGroup {
            WatchRootView(store: store)
                .task {
                    // The session must be live before boot so a context that is
                    // already waiting can supply a location.
                    startSession()
                    await store.boot()
                    WatchBackgroundRefresh.schedule()
                }
        }
        // §7.4 — refresh the forecast, reload complications, then queue the next.
        // PLAN DEVIATION §7.4: the watchOS `.appRefresh` task carries the
        // scheduler's `userInfo` string, so the action takes `String?`, not `Void`.
        .backgroundTask(.appRefresh) { (_: String?) in
            await WatchBackgroundRefresh.run()
        }
    }

    private func startSession() {
        guard session == nil else { return }
        let store = self.store
        let manager = WatchSessionManager { payload in
            Task { @MainActor in
                await store.applySyncedPayload(payload)
            }
        }
        manager.activate()
        session = manager
    }
}

/// §9 — vertical paging across the three pages.
struct WatchRootView: View {
    let store: WatchStore

    var body: some View {
        switch store.phase {
        case .loading:
            ProgressView()
        case .needsLocation:
            emptyState
        case .failed(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await store.refresh() } }
                    .font(.caption2)
            }
            .padding()
        case .loaded:
            TabView {
                NowPage(store: store)
                HourlyPage(store: store)
                DailyPage(store: store)
            }
            .tabViewStyle(.verticalPage)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Open the iPhone app to set a location")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
