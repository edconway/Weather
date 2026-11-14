import CoreLocation
import Foundation
import os
import WeatherCore
import WeatherKit

/// On-device WeatherKit for the iPhone app. Uses `WeatherService` only.
/// No REST host, no JWT signing, and no `.p8` key.
actor AppleWeatherClient {
    static let shared = AppleWeatherClient()

    private let service: WeatherService
    private let now: @Sendable () -> Date
    private let log = Logger(subsystem: AppConfig.iOSBundleID, category: "WeatherKit")
    private var lastNotAuthorisedAt: Date?
    private var cache: (key: String, snapshot: AppleWeatherSnapshot)?

    init(service: WeatherService = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    /// `bypassHoldOff` is pull-to-refresh: it skips the 15-minute auth pause and the cache.
    func fetch(latitude: Double, longitude: Double, bypassHoldOff: Bool) async -> AppleWeatherSnapshot {
        let key = String(format: "%.2f-%.2f", latitude, longitude)
        let now = now()
        if !bypassHoldOff, let cache, cache.key == key,
           AppleWeatherStatus.shouldCache(cache.snapshot, now: now) {
            return cache.snapshot
        }
        if AppleWeatherStatus.shouldHoldOff(
            lastNotAuthorisedAt: lastNotAuthorisedAt, now: now, bypass: bypassHoldOff) {
            log.error("WeatherKit held off after notAuthorised")
            return Self.failureSnapshot(.notAuthorised, now: now)
        }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        let snapshot = await fetchFromWeatherKit(location: location, now: now)
        if snapshot.failure == .notAuthorised {
            lastNotAuthorisedAt = now
        }
        if AppleWeatherStatus.shouldCache(snapshot, now: now) {
            cache = (key, snapshot)
        } else if cache?.key == key {
            cache = nil
        }
        return snapshot
    }

    /// Asks only for minute rain, alerts, and availability.
    ///
    /// A narrowed request once failed in some regions. If it throws anything
    /// other than an auth error, retry once with `weather(for:)`, which is still
    /// the on-device service. Auth errors are not retried.
    private func fetchFromWeatherKit(location: CLLocation, now: Date) async -> AppleWeatherSnapshot {
        do {
            let (minute, alerts, availability) = try await service.weather(
                for: location,
                including: .minute,
                .alerts,
                .availability)
            let snapshot = await snapshot(
                minute: minute, alerts: alerts, availability: availability, now: now)
            logSuccess(snapshot)
            return snapshot
        } catch {
            let failure = AppleWeatherStatus.classify(error)
            guard failure != .notAuthorised else {
                logFailure(error)
                return Self.failureSnapshot(failure, now: now)
            }
            do {
                let weather = try await service.weather(for: location)
                let snapshot = await snapshot(
                    minute: weather.minuteForecast,
                    alerts: weather.weatherAlerts,
                    availability: weather.availability,
                    now: now)
                logSuccess(snapshot)
                return snapshot
            } catch {
                logFailure(error)
                return Self.failureSnapshot(AppleWeatherStatus.classify(error), now: now)
            }
        }
    }

    private func snapshot(
        minute: Forecast<MinuteWeather>?,
        alerts: [WeatherAlert]?,
        availability: WeatherAvailability,
        now: Date
    ) async -> AppleWeatherSnapshot {
        let minuteAvailability: AppleMinuteAvailability =
            availability.minuteAvailability == .available ? .available : .unavailable
        let minutes: [AppleMinutePoint]
        let expiresAt: Date
        if minuteAvailability == .available, let minute {
            minutes = minute.map { item in
                let metresPerSecond = item.precipitationIntensity
                    .converted(to: UnitSpeed.metersPerSecond).value
                return AppleMinutePoint(
                    date: item.date,
                    intensityMillimetresPerHour: AppleWeatherStatus
                        .millimetresPerHour(fromMetresPerSecond: metresPerSecond),
                    chance: item.precipitationChance)
            }
            expiresAt = minute.metadata.expirationDate
        } else {
            minutes = []
            expiresAt = now.addingTimeInterval(10 * 60)
        }
        let mappedAlerts = (alerts ?? []).map {
            AppleWeatherAlert(summary: $0.summary, detailsURL: $0.detailsURL)
        }
        return AppleWeatherSnapshot(
            minutes: minutes,
            alerts: mappedAlerts,
            minuteAvailability: minuteAvailability,
            failure: nil,
            attribution: await fetchAttribution(),
            fetchedAt: now,
            expiresAt: expiresAt)
    }

    private func fetchAttribution() async -> AppleWeatherAttribution? {
        do {
            let attribution = try await service.attribution
            return AppleWeatherAttribution(
                serviceName: attribution.serviceName,
                legalPageURL: attribution.legalPageURL,
                legalAttributionText: attribution.legalAttributionText,
                markLightURL: attribution.combinedMarkLightURL,
                markDarkURL: attribution.combinedMarkDarkURL)
        } catch {
            log.error("WeatherKit attribution failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func logSuccess(_ snapshot: AppleWeatherSnapshot) {
        let availability = snapshot.minuteAvailability.rawValue
        let count = snapshot.minutes.count
        log.info("WeatherKit ok availability=\(availability, privacy: .public) minutes=\(count, privacy: .public)")
    }

    private func logFailure(_ error: Error) {
        let description = error.localizedDescription
        log.error("WeatherKit failed: \(description, privacy: .public)")
    }

    private static func failureSnapshot(_ failure: AppleWeatherFailure, now: Date) -> AppleWeatherSnapshot {
        AppleWeatherSnapshot(
            minutes: [],
            alerts: [],
            minuteAvailability: .unavailable,
            failure: failure,
            attribution: nil,
            fetchedAt: now,
            expiresAt: now)
    }
}
