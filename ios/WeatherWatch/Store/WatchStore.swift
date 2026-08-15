import Foundation
import Observation
import WeatherCore

/// The watch's single store (§9).
///
/// The watch fetches its own forecast directly but **never** calls the archive
/// API — normals arrive from the phone via WatchConnectivity, and are only
/// applied when they describe the same place (§9.2).
@Observable
@MainActor
final class WatchStore {

    enum Phase: Equatable {
        case loading
        case loaded
        case needsLocation
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var location: WeatherLocation?
    private(set) var forecast: ForecastResponse?
    private(set) var conditions: CurrentConditions?
    private(set) var syncedPayload: WatchSyncPayload?

    var imperial: Bool {
        didSet {
            guard imperial != oldValue else { return }
            prefs.imperial = imperial
        }
    }

    var formatter: UnitFormatter { UnitFormatter(imperial: imperial) }
    var locationTimeZone: TimeZone { forecast?.locationTimeZone ?? .current }

    private let client: OpenMeteoClient
    private let cache: DiskCache
    private let locationProvider: WatchLocationProvider
    private let geocoder: ReverseGeocoder
    private let prefs: Prefs
    private let now: () -> Date
    private var currentKey: String?

    init(
        client: OpenMeteoClient = OpenMeteoClient(),
        cache: DiskCache = DiskCache(),
        locationProvider: WatchLocationProvider = WatchLocationProvider(),
        // Nominatim's fallback is disabled here: a watch is the worst place to
        // spend battery on a second network round trip for a cosmetic label.
        geocoder: ReverseGeocoder = ReverseGeocoder(useNominatimFallback: false),
        prefs: Prefs = Prefs(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.client = client
        self.cache = cache
        self.locationProvider = locationProvider
        self.geocoder = geocoder
        self.prefs = prefs
        self.now = now
        self.imperial = prefs.imperial
    }

    // MARK: - Derived context

    /// Normals only count when the phone's payload is for (near) the same place.
    private var applicablePayload: WatchSyncPayload? {
        guard let syncedPayload, let location,
              WatchSyncEnvelope.isApplicable(syncedPayload, to: location) else { return nil }
        return syncedPayload
    }

    var hasContext: Bool { applicablePayload?.tempBand != nil }

    /// The single highest-priority badge (§9.1). Prefers phone-synced climate
    /// normals; falls back to a recent-days comparison so the watch still
    /// speaks without the iPhone.
    var badge: Anomaly? {
        guard let conditions else { return nil }

        if let payload = applicablePayload {
            if let synced = AnomalyEngine.watchBadge(
                conditions: conditions,
                tempBand: payload.tempBand,
                dailyRain: [],
                hourlyNormals: payload.chartHourlyNormals,
                formatter: formatter)
            {
                return Self.watchWording(synced, formatter: formatter)
            }
            if payload.tempBand != nil {
                return Anomaly(
                    text: "Near usual", kind: .neutral, panel: .temperature,
                    detail: "Today's high/low average is within 1°C of the usual "
                        + "reading for this date.")
            }
        }
        return recentDaysBadge
    }

    /// Compare today's mean to the mean of the past days already in the
    /// forecast window — no archive required.
    private var recentDaysBadge: Anomaly? {
        guard let today = dailyPoints.first(where: \.isToday),
              let todayHigh = today.high, let todayLow = today.low
        else { return nil }
        let past = dailyPoints.filter(\.isPast)
        let pastMeans = past.compactMap { point -> Double? in
            guard let h = point.high, let l = point.low else { return nil }
            return (h + l) / 2
        }
        guard !pastMeans.isEmpty else { return nil }

        let todayMean = (todayHigh + todayLow) / 2
        let baseline = pastMeans.reduce(0, +) / Double(pastMeans.count)
        let delta = todayMean - baseline
        let magnitude = abs(delta)

        if magnitude < 1 {
            return Anomaly(
                text: "Similar to recent days", kind: .neutral, panel: .temperature,
                detail: "Today's average is within 1°C of the last "
                    + "\(pastMeans.count) day" + (pastMeans.count == 1 ? "" : "s") + ".")
        }

        let displayed = Int(formatter.temperatureDelta(magnitude).rounded())
        let hotter = delta > 0
        let text: String
        if pastMeans.count == 1 {
            text = hotter
                ? "\(displayed)° hotter than yesterday"
                : "\(displayed)° colder than yesterday"
        } else {
            text = hotter
                ? "\(displayed)° hotter than usual lately"
                : "\(displayed)° colder than usual lately"
        }
        return Anomaly(
            text: text,
            kind: hotter ? .warm : .cold,
            panel: .temperature,
            detail: "Compared with the last \(pastMeans.count) day"
                + (pastMeans.count == 1 ? "" : "s")
                + " already on the watch.")
    }

    /// Friendlier watch copy for climate-backed badges ("hotter than usual"
    /// reads clearer at a glance than "warmer than normal").
    private static func watchWording(_ anomaly: Anomaly, formatter: UnitFormatter) -> Anomaly {
        switch anomaly.kind {
        case .warm:
            let rewritten = anomaly.text
                .replacingOccurrences(
                    of: formatter.temperatureUnit + " warmer than normal",
                    with: "° hotter than usual")
                .replacingOccurrences(of: " warmer than normal", with: " hotter than usual")
            return Anomaly(
                text: rewritten, kind: anomaly.kind, panel: anomaly.panel,
                detail: anomaly.detail)
        case .cold:
            let rewritten = anomaly.text
                .replacingOccurrences(
                    of: formatter.temperatureUnit + " colder than normal",
                    with: "° colder than usual")
                .replacingOccurrences(of: " colder than normal", with: " colder than usual")
            return Anomaly(
                text: rewritten, kind: anomaly.kind, panel: anomaly.panel,
                detail: anomaly.detail)
        default:
            return anomaly
        }
    }

    var hourlyPoints: [ChartSeries.HourlyPoint] {
        guard let forecast, let conditions else { return [] }
        return ChartSeries.hourly(
            forecast: forecast, conditions: conditions,
            normals: applicablePayload?.chartHourlyNormals)
    }

    /// Last 6 hours + next 6 hours (12 points straddling now).
    var recentAndNextHours: [ChartSeries.HourlyPoint] {
        let past = Array(hourlyPoints.filter(\.isPast).suffix(6))
        let future = Array(hourlyPoints.filter { !$0.isPast }.prefix(6))
        return past + future
    }

    var dailyPoints: [ChartSeries.DailyPoint] {
        guard let forecast, let conditions else { return [] }
        return ChartSeries.daily(
            forecast: forecast, conditions: conditions,
            tempBand: applicablePayload?.tempBand, dailyRain: [])
    }

    /// Last 3 days + today + next 3 (7 points straddling today).
    var recentAndForecastDays: [ChartSeries.DailyPoint] {
        let past = Array(dailyPoints.filter(\.isPast).suffix(3))
        let todayAndNext = Array(dailyPoints.filter { !$0.isPast }.prefix(4))
        return past + todayAndNext
    }

    // MARK: - Boot (§9.1)

    /// Cached last location → fresh fix → phone-synced location → empty state.
    func boot() async {
        if let cached = await cache.readFresh(WeatherLocation.self, kind: .lastLocation) {
            location = cached
            await loadForecast(for: cached)
        }
        await restoreSyncedPayload()

        if let fix = await locationProvider.currentLocation() {
            let previous = location
            let resolved = WeatherLocation(
                latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude,
                name: previous?.name ?? "", source: .geo)
            let movedElsewhere = resolved.cacheKey != previous?.cacheKey
            if movedElsewhere {
                location = resolved
                await loadForecast(for: resolved)
            }
            // Name it separately from the reload: a cached fix from a previous
            // launch has the right coordinates but may still be unnamed, and
            // gating the geocode on `movedElsewhere` would leave it that way
            // forever.
            if resolved.name.isEmpty {
                let name = await geocoder.name(
                    latitude: resolved.latitude, longitude: resolved.longitude)
                guard currentKey == resolved.cacheKey || !movedElsewhere else { return }
                let named = WeatherLocation(
                    latitude: resolved.latitude, longitude: resolved.longitude,
                    name: name, source: .geo)
                location = named
                await cache.write(named, kind: .lastLocation)
            }
        } else if location == nil, let synced = syncedPayload?.location {
            location = synced
            await loadForecast(for: synced)
        }

        if location == nil {
            phase = .needsLocation
        }
    }

    func refresh() async {
        guard let location else { return }
        await loadForecast(for: location, force: true)
    }

    private func loadForecast(for target: WeatherLocation, force: Bool = false) async {
        currentKey = target.cacheKey
        if !force,
           let cached = await cache.readFresh(
            ForecastResponse.self, kind: .forecast, location: target) {
            apply(cached, for: target)
            return
        }
        do {
            let response = try await client.forecast(
                latitude: target.latitude, longitude: target.longitude)
            guard currentKey == target.cacheKey else { return }
            await cache.write(response, kind: .forecast, location: target)
            await cache.write(target, kind: .lastLocation)
            apply(response, for: target)
        } catch {
            guard currentKey == target.cacheKey else { return }
            // Any cached copy beats an error on a glanceable device.
            if let stale = await cache.readIgnoringExpiry(
                ForecastResponse.self, kind: .forecast, location: target) {
                apply(stale.value, for: target)
            } else if forecast == nil {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func apply(_ response: ForecastResponse, for target: WeatherLocation) {
        forecast = response
        conditions = CurrentConditions(forecast: response, now: now())
        // Until the geocoder answers, borrow the phone's name for this place.
        if target.name.isEmpty, let synced = syncedPayload,
           WatchSyncEnvelope.isApplicable(synced, to: target) {
            location = WeatherLocation(
                latitude: target.latitude, longitude: target.longitude,
                name: synced.name, source: target.source)
        }
        phase = .loaded
    }

    // MARK: - WatchConnectivity (§9.2)

    func restoreSyncedPayload() async {
        if let cached = await cache.readFresh(WatchSyncPayload.self, kind: .watchPayload) {
            syncedPayload = cached
            imperial = cached.imperial
        }
    }

    /// Called by `WatchSessionManager` when a new application context arrives.
    func applySyncedPayload(_ payload: WatchSyncPayload) async {
        syncedPayload = payload
        imperial = payload.imperial
        prefs.imperial = payload.imperial
        await cache.write(payload, kind: .watchPayload)

        // With no location of our own yet, adopt the phone's.
        if location == nil {
            location = payload.location
            await loadForecast(for: payload.location)
        }
    }
}
