import SwiftUI
import WeatherCore
import WidgetKit

@main
struct WeatherScopeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WeatherStore()
    @State private var session = PhoneSessionManager()

    init() {
        // §7.4 — registration must happen before launch finishes.
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            TodayScreen(store: store)
                .preferredColorScheme(store.theme.colorScheme)
                .task { startSync() }
                .onOpenURL { url in
                    store.pendingPanelJump = AppConfig.panel(from: url)
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
    }

    /// Push normals and prefs to the watch after every successful build (§9.2),
    /// and keep widget timelines in step with what the app is showing (§10.3).
    private func startSync() {
        session.activate()
        let store = self.store
        let session = self.session
        let push: () -> Void = {
            guard let location = store.location else { return }
            let payload = WatchSyncPayload(
                location: location,
                imperial: store.imperial,
                tempBand: store.tempBand,
                climatology: store.climatology,
                hourlyNormals: store.hourlyNormals)
            session.send(payload)
            // Also persist it locally: this phone's *own* widget extension reads
            // normals from the App Group cache, and without this the iOS
            // "vs Normal" widget would permanently fall back to plain
            // conditions. App Groups don't cross devices, so this write and the
            // WatchConnectivity send are two separate jobs (§14.6).
            if !payload.isEmpty {
                Task { await DiskCache().write(payload, kind: .watchPayload) }
            }
            WidgetReloadThrottle.reloadIfDue()
        }
        store.onDataChanged = push
        store.onPrefsChanged = push
        // Re-push when a watch appears or reinstalls the app.
        session.onNeedsResend = push
    }
}
