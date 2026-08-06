import Foundation
import Observation
import SwiftUI
import WeatherCore

/// The single screen-level store (§7.2, §8.1).
///
/// Loading is progressive, exactly like the web app: the forecast publishes as
/// soon as it lands so the hero renders, and the archive-derived pieces fill in
/// behind it. Every async result is tagged with the location key it was started
/// for and dropped if the user has since switched location (§14.9).
@Observable
@MainActor
final class WeatherStore {

    enum Phase: Equatable {
        case idle
        case locating
        case loading
        case loaded
        /// No data and no location — the web's `showSearchFirst`.
        case searchFirst(String?)
        /// No data at all — the web's `showErr`, full screen with Try Again.
        case failed(String)
    }

    // MARK: - Published state

    private(set) var phase: Phase = .idle
    private(set) var location: WeatherLocation?
    private(set) var forecast: ForecastResponse?
    private(set) var conditions: CurrentConditions?
    private(set) var tempBand: TempBand?
    private(set) var dailyRain: [DailyRainNormal] = []
    private(set) var hourlyNormals: HourlyNormals?
    private(set) var climatology: Climatology?
    private(set) var ytdRain: YTDRain?
    private(set) var ytdProjection: [YTDRainBuilder.ProjectionPoint] = []

    /// Set by a widget/complication deep link; `TodayScreen` observes this to
    /// scroll to the matching panel, then clears it.
    var pendingPanelJump: PanelID?

    /// Non-blocking message shown over existing data (stale cache, a failed
    /// background piece) — the web app's banner case.
    private(set) var banner: String?
    private(set) var isRefreshing = false

    /// Both known locations, so the source toggle can appear (§8.2).
    private(set) var geoLocation: WeatherLocation?
    private(set) var customLocation: WeatherLocation?
    private(set) var activeSource: WeatherLocation.Source = .geo

    var imperial: Bool {
        didSet {
            guard imperial != oldValue else { return }
            prefs.imperial = imperial
            onPrefsChanged?()
        }
    }

    var theme: Prefs.ThemeOverride {
        didSet {
            guard theme != oldValue else { return }
            prefs.theme = theme
        }
    }

    var formatter: UnitFormatter { UnitFormatter(imperial: imperial) }

    /// Set by the app to push prefs/normals to the watch (Phase 5).
    var onPrefsChanged: (() -> Void)?
    var onDataChanged: (() -> Void)?

    // MARK: - Collaborators

    private let repository: WeatherRepository
    private let locationProvider: LocationProvider
    private let geocoder: ReverseGeocoder
    private let prefs: Prefs
    private let now: () -> Date

    /// Guards against a slow response for a location the user has left.
    private var currentKey: String?
    private var loadTasks: [Task<Void, Never>] = []
    private var ytdRequested = false
    private var climatologyRequested = false

    init(
        repository: WeatherRepository = WeatherRepository(),
        locationProvider: LocationProvider = LocationProvider(),
        geocoder: ReverseGeocoder = ReverseGeocoder(),
        prefs: Prefs = Prefs(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.locationProvider = locationProvider
        self.geocoder = geocoder
        self.prefs = prefs
        self.now = now
        self.imperial = prefs.imperial
        self.theme = prefs.theme
        self.geoLocation = prefs.lastGeoLocation
        self.customLocation = prefs.customLocation
        self.activeSource = prefs.activeSource
    }

    /// Both sources exist, so the toggle capsule is worth showing.
    var showsSourceToggle: Bool { geoLocation != nil && customLocation != nil }

    /// The location's own timezone drives every "now" (§1.4.2).
    var locationTimeZone: TimeZone { forecast?.locationTimeZone ?? .current }

    var heroBadges: [Anomaly] {
        guard let conditions else { return [] }
        return AnomalyEngine.heroBadges(
            conditions: conditions, tempBand: tempBand, dailyRain: dailyRain,
            hourlyNormals: hourlyNormals, formatter: formatter)
    }

    // MARK: - Chart inputs
    //
    // Recomputed on demand rather than cached: SwiftUI only asks while the
    // relevant panel is on screen, and the arrays are small (72 / 14 points).
    // The YTD series is the exception — see `ytdSeries`.

    var hourlyPoints: [ChartSeries.HourlyPoint] {
        guard let forecast, let conditions else { return [] }
        return ChartSeries.hourly(
            forecast: forecast, conditions: conditions, normals: hourlyNormals)
    }

    var dailyPoints: [ChartSeries.DailyPoint] {
        guard let forecast, let conditions else { return [] }
        return ChartSeries.daily(
            forecast: forecast, conditions: conditions,
            tempBand: tempBand, dailyRain: dailyRain)
    }

    /// Built once when the YTD data lands rather than on every redraw — this is
    /// the ~365-point series and rebuilding it during a scroll is visible.
    private(set) var ytdSeries: ChartSeries.YTDSeries?

    /// Formatted date line under the location name.
    var dateLine: String {
        guard let forecast, let conditions,
              let date = DateKit(timeZone: forecast.locationTimeZone)
                .date(fromDayString: conditions.todayString)
        else { return "" }
        var style = Date.FormatStyle()
            .weekday(.wide).year(.defaultDigits).month(.wide).day(.defaultDigits)
        style.timeZone = forecast.locationTimeZone
        return date.formatted(style)
    }

    // MARK: - Boot (§8.1)

    func boot() async {
        // 1. A saved custom location loads straight away — no location prompt.
        if prefs.activeSource == .custom, let saved = prefs.customLocation {
            await load(saved)
            return
        }
        await loadFromDeviceLocation()
    }

    func loadFromDeviceLocation() async {
        phase = .locating
        do {
            let fix = try await locationProvider.currentLocation()
            let name = await geocoder.name(
                latitude: fix.coordinate.latitude, longitude: fix.coordinate.longitude)
            let resolved = WeatherLocation(
                latitude: fix.coordinate.latitude,
                longitude: fix.coordinate.longitude,
                name: name, source: .geo)
            geoLocation = resolved
            prefs.lastGeoLocation = resolved
            await load(resolved)
        } catch {
            // 3. No fix and no data → search-first. With data → banner.
            if forecast == nil {
                // A previously-saved GPS location beats an empty screen.
                if let saved = prefs.lastGeoLocation {
                    geoLocation = saved
                    await load(saved)
                } else {
                    phase = .searchFirst(error.localizedDescription)
                }
            } else {
                banner = error.localizedDescription
            }
        }
    }

    // MARK: - Loading

    func load(_ target: WeatherLocation) async {
        cancelInFlight()
        resetDerivedData()

        location = target
        activeSource = target.source
        currentKey = target.cacheKey
        prefs.activeSource = target.source
        switch target.source {
        case .geo:
            geoLocation = target
            prefs.lastGeoLocation = target
        case .custom:
            customLocation = target
            prefs.customLocation = target
        }

        if forecast == nil { phase = .loading }

        do {
            let fetched = try await repository.forecast(for: target)
            guard currentKey == target.cacheKey else { return }

            forecast = fetched.value
            conditions = CurrentConditions(forecast: fetched.value, now: now())
            phase = .loaded
            banner = fetched.isStale ? Self.staleBannerText(savedAt: fetched.savedAt) : nil
            onDataChanged?()

            startBackgroundLoads(for: target)
        } catch {
            guard currentKey == target.cacheKey else { return }
            // 4. Errors before any data → full-screen; after → banner.
            if forecast == nil {
                phase = .failed(error.localizedDescription)
            } else {
                phase = .loaded
                banner = error.localizedDescription
            }
        }
    }

    func retry() async {
        if let location {
            await load(location)
        } else {
            await boot()
        }
    }

    /// Pull-to-refresh: bypasses the forecast TTL.
    func refresh() async {
        guard let location else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let response = try await repository.refreshForecast(for: location)
            guard currentKey == location.cacheKey else { return }
            forecast = response
            conditions = CurrentConditions(forecast: response, now: now())
            banner = nil
            onDataChanged?()
        } catch {
            banner = error.localizedDescription
        }
    }

    private static func staleBannerText(savedAt: Date?) -> String {
        guard let savedAt else { return "Showing saved data — couldn't reach the network." }
        let relative = savedAt.formatted(.relative(presentation: .named))
        return "Showing data from \(relative) — couldn't reach the network."
    }

    // MARK: - Progressive archive loads (§7.2)

    private func startBackgroundLoads(for target: WeatherLocation) {
        // Hourly normals always start immediately — the mugginess badge and the
        // hourly chart overlays both want them, and they are cheap to cache.
        loadTasks.append(Task { [weak self] in
            await self?.loadHourlyNormals(for: target)
        })
    }

    private func loadHourlyNormals(for target: WeatherLocation) async {
        let timeZone = forecast?.locationTimeZone ?? .current
        guard let normals = try? await repository.hourlyNormals(
            for: target, now: now(), timeZone: timeZone) else { return }
        guard currentKey == target.cacheKey else { return }
        hourlyNormals = normals
        onDataChanged?()
    }

    /// §1.4.7 — called from the temperature panel's `onAppear`, replacing the
    /// web's IntersectionObserver.
    func ensureClimatology() {
        guard !climatologyRequested, let target = location else { return }
        climatologyRequested = true
        loadTasks.append(Task { [weak self] in
            await self?.loadClimatology(for: target)
        })
    }

    private func loadClimatology(for target: WeatherLocation) async {
        let timeZone = forecast?.locationTimeZone ?? .current
        do {
            let climate = try await repository.climatology(
                for: target, now: now(), timeZone: timeZone)
            guard currentKey == target.cacheKey else { return }
            climatology = climate
            tempBand = TempBandDeriver.derive(
                climatology: climate, now: now(), timeZone: timeZone)
            if let forecast, let conditions {
                dailyRain = DailyRainDeriver.derive(
                    forecast: forecast, climatology: climate,
                    todayIndex: conditions.todayIndex)
            }
            onDataChanged?()
        } catch {
            guard currentKey == target.cacheKey else { return }
            // Silent: the hero and forecast-only charts remain perfectly usable.
            climatologyRequested = false
        }
    }

    /// Called from the YTD chart's `onAppear`.
    func ensureYTD() {
        guard !ytdRequested, let target = location else { return }
        ytdRequested = true
        loadTasks.append(Task { [weak self] in
            await self?.loadYTD(for: target)
        })
    }

    private func loadYTD(for target: WeatherLocation) async {
        let timeZone = forecast?.locationTimeZone ?? .current
        do {
            let ytd = try await repository.ytdRain(
                for: target, now: now(), timeZone: timeZone)
            guard currentKey == target.cacheKey else { return }
            ytdRain = ytd
            if let forecast {
                ytdProjection = YTDRainBuilder.projection(forecast: forecast, ytd: ytd)
            }
            rebuildYTDSeries()
        } catch {
            guard currentKey == target.cacheKey else { return }
            ytdRequested = false
        }
    }

    /// §8.4.7 — thin the heaviest chart once a year's worth of points would be
    /// indistinguishable anyway.
    private func rebuildYTDSeries() {
        guard let ytdRain else {
            ytdSeries = nil
            return
        }
        ytdSeries = ChartSeries.ytd(
            ytd: ytdRain,
            projection: ytdProjection,
            timeZone: forecast?.locationTimeZone ?? .current,
            thinning: ytdRain.labels.count > 240 ? 2 : 1)
    }

    // MARK: - Location switching

    func selectSearchResult(_ result: GeocodingResponse.Result) async {
        let picked = WeatherLocation(
            latitude: result.latitude, longitude: result.longitude,
            name: result.displayName, source: .custom)
        customLocation = picked
        prefs.customLocation = picked
        await load(picked)
    }

    func switchSource(to source: WeatherLocation.Source) async {
        guard source != activeSource else { return }
        switch source {
        case .geo:
            if let geoLocation {
                await load(geoLocation)
            } else {
                await loadFromDeviceLocation()
            }
        case .custom:
            guard let customLocation else { return }
            await load(customLocation)
        }
    }

    func dismissBanner() { banner = nil }

    // MARK: - Resetting

    private func cancelInFlight() {
        loadTasks.forEach { $0.cancel() }
        loadTasks.removeAll()
    }

    /// Port of `resetWeatherData` + `resetLazyState`.
    private func resetDerivedData() {
        tempBand = nil
        dailyRain = []
        hourlyNormals = nil
        climatology = nil
        ytdRain = nil
        ytdProjection = []
        ytdSeries = nil
        ytdRequested = false
        climatologyRequested = false
        banner = nil
    }
}
