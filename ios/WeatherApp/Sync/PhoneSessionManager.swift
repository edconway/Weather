import Foundation
import OSLog
import WatchConnectivity
import WeatherCore

private let log = Logger(subsystem: "com.edconway.weatherworld", category: "watch-sync")

/// Phone side of WatchConnectivity (§9.2).
///
/// `updateApplicationContext` replaces whatever was queued, so sending on every
/// data change costs nothing and the watch always wakes to the latest normals.
/// Failures are retried on the next activation rather than queued by hand — the
/// context *is* the queue.
final class PhoneSessionManager: NSObject, WCSessionDelegate {
    private var pendingContext: [String: Any]?
    private var lastSentDescriptor: String?

    /// Asks the owner to hand over the current payload again, for cases where
    /// there is nothing queued but the watch's state has been reset.
    var onNeedsResend: (() -> Void)?

    override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends the latest derived context. Cheap to call repeatedly — a payload
    /// identical to the last one is dropped.
    func send(_ payload: WatchSyncPayload) {
        guard !payload.isEmpty else { return }
        let descriptor = "\(payload.latitude),\(payload.longitude),\(payload.imperial),"
            + "\(payload.dailyAvg.count),\(payload.monthlyNormals.count),\(payload.wbAvgByHour.count)"
        guard descriptor != lastSentDescriptor else { return }

        guard let context = try? WatchSyncEnvelope.encode(payload) else { return }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        guard session.activationState == .activated else {
            // Retried from `activationDidCompleteWith`.
            pendingContext = context
            log.notice("session not activated yet; context queued")
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            // Perfectly normal — most users have no watch. Keep the context so
            // it goes out if one is paired later.
            pendingContext = context
            log.notice("no watch to send to: paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
            return
        }
        do {
            try session.updateApplicationContext(context)
            lastSentDescriptor = descriptor
            pendingContext = nil
            log.notice("sent watch context for \(payload.name, privacy: .public)")
        } catch {
            pendingContext = context
            log.error("updateApplicationContext failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func flushPending() {
        guard let context = pendingContext, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(context)
            pendingContext = nil
            log.notice("flushed queued watch context")
        } catch {
            log.error("flush failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reason = error?.localizedDescription ?? "none"
        log.notice("phone session activated: state=\(activationState.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) error=\(reason, privacy: .public)")
        guard activationState == .activated else { return }
        flushPending()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        // Fires when the watch app is installed or a watch is paired — the
        // moment a previously undeliverable context becomes deliverable.
        log.notice("watch state changed: paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
        // A reinstalled watch app starts with an empty cache, so the dedupe
        // must forget what it "already sent" or the watch never gets context.
        lastSentDescriptor = nil
        flushPending()
        onNeedsResend?()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching watches invalidates the session; reactivate so a new watch
    /// gets the context too.
    func sessionDidDeactivate(_ session: WCSession) {
        lastSentDescriptor = nil
        WCSession.default.activate()
    }
}
