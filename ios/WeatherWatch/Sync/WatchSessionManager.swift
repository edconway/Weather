import Foundation
import OSLog
import WatchConnectivity
import WeatherCore

private let log = Logger(subsystem: "com.edconway.weatherworld", category: "watch-sync")

/// Watch side of WatchConnectivity (§9.2).
///
/// Only `updateApplicationContext` is used: it always delivers the *latest*
/// state and coalesces, which is exactly right for "here are the current
/// normals" — unlike message sending, which needs both sides awake.
final class WatchSessionManager: NSObject, WCSessionDelegate {
    private let onPayload: @Sendable (WatchSyncPayload) -> Void

    init(onPayload: @escaping @Sendable (WatchSyncPayload) -> Void) {
        self.onPayload = onPayload
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// The context that was already waiting when the app launched.
    func deliverPendingContext() {
        guard WCSession.isSupported() else { return }
        let context = WCSession.default.receivedApplicationContext
        if let payload = WatchSyncEnvelope.decode(context) {
            log.notice("restored pending context for \(payload.name, privacy: .public)")
            onPayload(payload)
        } else {
            log.notice("no pending context (keys: \(context.keys.joined(separator: ","), privacy: .public))")
        }
    }

    func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reason = error?.localizedDescription ?? "none"
        log.notice("watch session activated: state=\(activationState.rawValue) reachable=\(session.isReachable) error=\(reason, privacy: .public)")
        guard activationState == .activated else { return }
        deliverPendingContext()
    }

    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let payload = WatchSyncEnvelope.decode(context) else {
            log.error("received an undecodable application context")
            return
        }
        log.notice("received context for \(payload.name, privacy: .public)")
        onPayload(payload)
    }
}
