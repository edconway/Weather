import CoreLocation
import Foundation
import WeatherCore

/// One-shot when-in-use location fix (§8.1 step 2).
///
/// Mirrors the web app's `getPos`: a 15 s timeout, and a cached fix up to 5
/// minutes old is good enough (the browser's `maximumAge: 300000`).
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutTask: Task<Void, Never>?

    static let maximumCachedFixAge: TimeInterval = 5 * 60
    static let timeout: Duration = .seconds(15)

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var isDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    /// Requests authorization if needed, then resolves one fix.
    func currentLocation() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if isDenied { throw WeatherErrorBridge.denied }

        // A recent cached fix avoids spinning up the radio at all.
        if let cached = manager.location,
           Date().timeIntervalSince(cached.timestamp) <= Self.maximumCachedFixAge {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.timeout)
                guard !Task.isCancelled else { return }
                self?.finish(.failure(WeatherErrorBridge.timedOut))
            }
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(WeatherErrorBridge.unavailable))
            return
        }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code
        finish(.failure(code == .denied ? WeatherErrorBridge.denied : WeatherErrorBridge.unavailable))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // The first `requestLocation` before authorization lands is a no-op, so
        // retry once permission is granted while we are still waiting.
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(.failure(WeatherErrorBridge.denied))
        default:
            break
        }
    }
}

/// `WeatherError` lives in WeatherCore, which does not import CoreLocation's
/// error vocabulary; this keeps the mapping in one place.
enum WeatherErrorBridge {
    static let denied = WeatherError.locationDenied
    static let unavailable = WeatherError.locationUnavailable
    static let timedOut = WeatherError.locationTimeout
}
