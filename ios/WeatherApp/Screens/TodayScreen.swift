import SwiftUI
import WeatherCore

/// The single scrolling screen (§8.2): atmosphere hero, native sections, charts.
struct TodayScreen: View {
    @Bindable var store: WeatherStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showingSearch = false
    @State private var showingSettings = false
    @State private var detailKind: ChartDetailSheet.Kind?
    /// Shared across every chart on this screen so scrubbing one clears
    /// whichever other chart's readout was pinned — see `StickyXSelection`.
    @State private var scrubCoordinator = ActiveScrubCoordinator()
    @State private var pinProgress: CGFloat = 0
    @State private var topInset: CGFloat = 47
    @State private var selectedPanel: PanelID = .temperature
    @State private var segmentLock: PanelID?
    @State private var wetBulbExpanded = false
    /// Width of the scene, updated when the window resizes or the phone folds.
    @State private var canvasWidth: CGFloat = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("")
                .toolbar(.hidden, for: .navigationBar)
        }
        .environment(scrubCoordinator)
        .sheet(isPresented: $showingSearch) {
            SearchSheet { result in
                Task { await store.selectSearchResult(result) }
            }
            .readableWhenRegular()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(store: store)
                .readableWhenRegular()
        }
        .sheet(item: $detailKind) { kind in
            ChartDetailSheet(kind: kind, store: store)
                .readableWhenRegular()
        }
        .task { await store.boot() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .locating:
            LoadingView(message: "Getting your location…")
        case .loading:
            LoadingView(message: "Loading weather…")
        case .failed(let message):
            VStack(spacing: 0) {
                chromeHeader(overAtmosphere: false)
                ErrorView(message: message) {
                    Task { await store.retry() }
                }
            }
        case .searchFirst(let hint):
            VStack(spacing: 0) {
                chromeHeader(overAtmosphere: false)
                SearchFirstView(hint: hint) { showingSearch = true }
            }
        case .loaded:
            loadedScroll
        }
    }

    private var loadedScroll: some View {
        ScrollViewReader { proxy in
            Group {
                if StatusCanvas.prefersSplit(horizontal: horizontalSizeClass, width: canvasWidth) {
                    splitCanvas(proxy: proxy)
                } else {
                    compactCanvas(proxy: proxy)
                }
            }
            .background { CanvasWidthReader(width: $canvasWidth) }
            .background { WindowTopInset(top: $topInset) }
            .onChange(of: store.pendingPanelJump) { _, panel in
                guard let panel else { return }
                jump(panel, proxy: proxy)
                store.pendingPanelJump = nil
            }
            .onChange(of: store.location?.cacheKey) { _, _ in
                wetBulbExpanded = false
            }
        }
    }

    /// Cover display, and any regular window that is still too narrow to split.
    private func compactCanvas(proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero(proxy: proxy)
                    sheet(proxy: proxy, tucked: true, sideBySide: false)
                }
            }
            .coordinateSpace(name: "today")
            .ignoresSafeArea(edges: .top)
            .refreshable { await store.refresh() }
            .onPreferenceChange(HeroBottomPreference.self) { bottom in
                pinProgress = min(1, max(0, (118 - bottom) / 24))
            }
            .onPreferenceChange(SectionTopsPreference.self) { tops in
                guard segmentLock == nil else { return }
                let bar: CGFloat = pinProgress > 0.55 ? 120 : 24
                var current = PanelID.temperature
                for panel in [PanelID.temperature, .wetBulb, .rain, .climate] {
                    if let top = tops[panel], top - bar <= 56 { current = panel }
                }
                if selectedPanel != current { selectedPanel = current }
            }

            if let conditions = store.conditions, pinProgress > 0.02 {
                PinnedHeader(
                    placeName: placeName,
                    showsGPS: store.activeSource == .geo,
                    nowLine: nowLine(conditions),
                    updated: ScreenPresentation.updatedPhrase(
                        fetchedAt: store.forecastUpdatedAt,
                        now: Date(),
                        timeZone: store.locationTimeZone).text,
                    selected: selectedPanel,
                    onPlace: { showingSearch = true },
                    onSelect: { jump($0, proxy: proxy) }
                )
                .opacity(pinProgress)
                .allowsHitTesting(pinProgress > 0.55)
                .accessibilityHidden(pinProgress < 0.55)
            }
        }
    }

    /// Unfolded regular width: status stays in one column, charts scroll in the other.
    private func splitCanvas(proxy: ScrollViewProxy) -> some View {
        let statusWidth = StatusCanvas.statusWidth(in: canvasWidth)
        let detailWidth = max(0, canvasWidth - statusWidth)
        return HStack(alignment: .top, spacing: 0) {
            GeometryReader { column in
                ScrollView {
                    hero(proxy: proxy)
                        .frame(minHeight: column.size.height, alignment: .top)
                }
                .ignoresSafeArea(edges: .top)
            }
            .frame(width: statusWidth)
            .frame(maxHeight: .infinity)

            Divider()

            ScrollView {
                sheet(
                    proxy: proxy,
                    tucked: false,
                    sideBySide: detailWidth >= StatusCanvas.chartPairMinimum)
            }
            .frame(maxHeight: .infinity)
            .coordinateSpace(name: "today")
            .background(Color(.systemBackground))
            .refreshable { await store.refresh() }
            .onPreferenceChange(SectionTopsPreference.self) { tops in
                guard segmentLock == nil else { return }
                var current = PanelID.temperature
                for panel in [PanelID.temperature, .wetBulb, .rain, .climate] {
                    if let top = tops[panel], top <= 80 { current = panel }
                }
                if selectedPanel != current { selectedPanel = current }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func hero(proxy: ScrollViewProxy) -> some View {
        if let conditions = store.conditions, let forecast = store.forecast {
            HeroView(
                placeName: placeName,
                showsGPS: store.activeSource == .geo,
                conditions: conditions,
                voice: voice(forecast: forecast, conditions: conditions),
                gauge: gaugeData(conditions),
                gaugeSeed: TemperatureGaugeSeed(
                    locationID: store.location?.cacheKey ?? "",
                    day: conditions.todayString),
                temperatureUnit: store.imperial ? .fahrenheit : .celsius,
                sun: TodaySun.today(forecast: forecast, dayIndex: conditions.todayIndex),
                outlook: outlook(forecast: forecast, conditions: conditions),
                topInset: topInset,
                formatter: store.formatter,
                onSearch: { showingSearch = true },
                onSettings: { showingSettings = true },
                onVoice: { jump($0, proxy: proxy) }
            )
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: HeroBottomPreference.self,
                        value: geo.frame(in: .named("today")).maxY)
                }
            }
        }
    }

    private var placeName: String {
        ScreenPresentation.shortPlaceName(store.location?.name ?? "Choose a place")
    }

    private func nowLine(_ conditions: CurrentConditions) -> String {
        let temp = store.formatter.temperatureNumber(conditions.temperature).map { "\($0)°" } ?? "—"
        return "\(temp) · \(conditions.condition.label)"
    }

    private func voice(
        forecast: ForecastResponse, conditions: CurrentConditions
    ) -> ScreenPresentation.HeroVoice? {
        ScreenPresentation.heroVoice(
            forecast: forecast, conditions: conditions,
            hourlyNormals: store.hourlyNormals, tempBand: store.tempBand,
            dailyRain: store.dailyRain, formatter: store.formatter)
    }

    private func gaugeData(_ conditions: CurrentConditions) -> TemperatureRangeData? {
        guard let low = conditions.low, let high = conditions.high else { return nil }
        return TemperatureRangeData(
            todayLow: low,
            todayHigh: high,
            current: conditions.temperature,
            averageLow: store.tempBand?.today?.tMin,
            averageHigh: store.tempBand?.today?.tMax)
    }

    private func outlook(
        forecast: ForecastResponse, conditions: CurrentConditions
    ) -> ScreenPresentation.RainOutlook {
        ScreenPresentation.rainOutlook(
            forecast: forecast, conditions: conditions, formatter: store.formatter)
    }

    private func jump(_ panel: PanelID, proxy: ScrollViewProxy) {
        selectedPanel = panel
        segmentLock = panel
        withAnimation { proxy.scrollTo(panel, anchor: UnitPoint(x: 0.5, y: 0.12)) }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            if segmentLock == panel { segmentLock = nil }
        }
    }

    private func sheet(proxy: ScrollViewProxy, tucked: Bool, sideBySide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let banner = store.banner {
                BannerView(message: banner) { store.dismissBanner() }
            }

            SectionSegmentBar(selected: selectedPanel) { jump($0, proxy: proxy) }

            if let forecast = store.forecast, let conditions = store.conditions {
                rainLead(forecast: forecast, conditions: conditions)
            }

            if store.showsSourceToggle {
                SourceToggle(
                    activeSource: store.activeSource,
                    customShortName: store.customLocation?.shortName ?? "Custom"
                ) { source in
                    Task { await store.switchSource(to: source) }
                }
            }

            panels(sideBySide: sideBySide)

            footer
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: tucked ? 26 : 0,
                bottomLeading: 0,
                bottomTrailing: 0,
                topTrailing: tucked ? 26 : 0),
            style: .continuous))
        .padding(.top, tucked ? -26 : 0)
    }

    @ViewBuilder
    private func rainLead(forecast: ForecastResponse, conditions: CurrentConditions) -> some View {
        let minutes = store.appleWeather?.displayMinutes ?? []
        let appleWet = minutes.contains { $0.intensityMillimetresPerHour > 0 }
        let hourly = outlook(forecast: forecast, conditions: conditions)
        if !minutes.isEmpty {
            NextHourCard(
                minutes: minutes,
                placeLabel: store.applePointLabel ?? store.location.map {
                    PrecisePlaceLabel.coordinates(latitude: $0.latitude, longitude: $0.longitude)
                } ?? "",
                attribution: store.appleWeather?.attribution,
                formatter: store.formatter,
                timeZone: store.locationTimeZone,
                emphasize: appleWet)
        }
        if minutes.isEmpty || (!appleWet && hourly.state != .dry) {
            OutlookCard(outlook: hourly)
        }
        if let alerts = store.appleWeather?.alerts, !alerts.isEmpty,
           store.appleWeather?.failure == nil {
            AppleAlertsList(alerts: alerts)
            if minutes.isEmpty, let attribution = store.appleWeather?.attribution {
                AppleAttributionView(attribution: attribution)
            }
        }
    }

    // MARK: - Chrome

    private func chromeHeader(overAtmosphere: Bool) -> some View {
        HStack(alignment: .center) {
            Button {
                showingSearch = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.caption.weight(.semibold))
                    Text(store.location?.name ?? "—")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Location: \(store.location?.name ?? "not set")")
            .accessibilityHint("Search for a different location")

            Spacer(minLength: 8)

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, overAtmosphere ? 56 : 8)
        .foregroundStyle(overAtmosphere ? Color.primary : Color.primary)
    }

    // MARK: - Panels

    @ViewBuilder
    private func panels(sideBySide: Bool) -> some View {
        let timeZone = store.locationTimeZone

        WeatherSection(
            id: .temperature,
            title: "Temperature",
            caption: "Actual air temp, high & low"
        ) {
            chartPair(sideBySide: sideBySide) {
                HourlyTempChart(
                    points: store.hourlyPoints, series: .temperature,
                    formatter: store.formatter, timeZone: timeZone,
                    detailText: Subtitles.hourlyTemp(store),
                    onOpenDetail: { detailKind = .hourlyTemp })
            } second: {
                DailyTempChart(
                    points: store.dailyPoints, series: .temperature,
                    formatter: store.formatter, timeZone: timeZone,
                    detailText: Subtitles.dailyTemp(store),
                    onOpenDetail: { detailKind = .dailyTemp })
            }
        }
        .background { sectionTop(.temperature) }
        .onAppear {
            // Kick off the slow archive fetches as soon as the first panel is
            // on screen, so YTD/climate aren't still spinning when the user
            // reaches the bottom.
            store.ensureClimatology()
            store.ensureYTD()
        }

        WeatherSection(
            id: .wetBulb,
            title: "Wet bulb",
            caption: wetBulbCollapsed ? "No heat stress" : "Heat stress"
        ) {
            if wetBulbCollapsed {
                WetBulbCollapsedCard(
                    now: store.formatter.temperatureShort(store.conditions?.wetBulbNow),
                    detail: wetBulbHiddenDetail,
                    onExpand: { wetBulbExpanded = true })
            } else {
                if wetBulbExpanded, let peak = wetBulbPeak, peak < 15 {
                    Button("Hide charts") { wetBulbExpanded = false }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                }
                chartPair(sideBySide: sideBySide) {
                    HourlyTempChart(
                        points: store.hourlyPoints, series: .wetBulb,
                        formatter: store.formatter, timeZone: timeZone,
                        detailText: Subtitles.hourlyWetBulb(store),
                        onOpenDetail: { detailKind = .hourlyWetBulb })
                } second: {
                    DailyTempChart(
                        points: store.dailyPoints, series: .wetBulb,
                        formatter: store.formatter, timeZone: timeZone,
                        detailText: Subtitles.dailyWetBulb(store),
                        onOpenDetail: { detailKind = .dailyWetBulb })
                }
            }
        }
        .background { sectionTop(.wetBulb) }

        WeatherSection(
            id: .rain,
            title: "Rain",
            caption: "Precipitation"
        ) {
            if let forecast = store.forecast, let conditions = store.conditions {
                RainTotalsRow(
                    totals: ScreenPresentation.rainTotals(
                        forecast: forecast, conditions: conditions, dailyRain: store.dailyRain),
                    formatter: store.formatter)
            }
            chartPair(sideBySide: sideBySide) {
                HourlyRainChart(
                    points: store.hourlyPoints,
                    formatter: store.formatter, timeZone: timeZone,
                    detailText: Subtitles.hourlyRain(store),
                    onOpenDetail: { detailKind = .hourlyRain })
            } second: {
                DailyRainChart(
                    points: store.dailyPoints,
                    formatter: store.formatter, timeZone: timeZone,
                    detailText: Subtitles.dailyRain(store),
                    onOpenDetail: { detailKind = .dailyRain })
            }
            if let series = store.ytdSeries {
                YTDRainChart(
                    series: series, formatter: store.formatter,
                    thisYear: store.ytdRain?.thisYear ?? 0, timeZone: timeZone,
                    detailText: Subtitles.ytdRain(store),
                    onOpenDetail: { detailKind = .ytdRain })
            } else {
                ChartPlaceholder(message: "Loading year-to-date rainfall…")
                    // Retry if the first archive fetch failed — section
                    // `onAppear` only fires once.
                    .onAppear { store.ensureYTD() }
            }
        }
        .background { sectionTop(.rain) }
        .onAppear { store.ensureYTD() }

        WeatherSection(
            id: .climate,
            title: "Climate",
            caption: "Monthly normals"
        ) {
            if let climatology = store.climatology {
                ClimateChart(
                    points: ChartSeries.climate(climatology),
                    formatter: store.formatter,
                    detailText: Subtitles.climate(store),
                    onOpenDetail: { detailKind = .climate })
            } else {
                ChartPlaceholder(message: "Loading climate data…")
                    .onAppear { store.ensureClimatology() }
            }
        }
        .background { sectionTop(.climate) }
        .onAppear { store.ensureClimatology() }
    }

    @ViewBuilder
    private func chartPair<First: View, Second: View>(
        sideBySide: Bool,
        @ViewBuilder first: () -> First,
        @ViewBuilder second: () -> Second
    ) -> some View {
        if sideBySide {
            HStack(alignment: .top, spacing: 16) {
                first().frame(maxWidth: .infinity, alignment: .leading)
                second().frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                first()
                second()
            }
        }
    }

    private func sectionTop(_ panel: PanelID) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: SectionTopsPreference.self,
                value: [panel: geo.frame(in: .named("today")).minY])
        }
    }

    private var wetBulbPeak: Double? {
        store.forecast.flatMap(ScreenPresentation.maxWetBulb)
    }

    private var wetBulbCollapsed: Bool {
        guard !wetBulbExpanded, let peak = wetBulbPeak else { return false }
        return peak < 15
    }

    private var wetBulbHiddenDetail: String {
        guard let conditions = store.conditions else {
            return "Charts hidden while it stays under 15°."
        }
        return ScreenPresentation.wetBulbHiddenDetail(
            conditions: conditions, hourlyNormals: store.hourlyNormals, formatter: store.formatter)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Forecast & historical data from Open-Meteo")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Link("open-meteo.com", destination: URL(string: "https://open-meteo.com")!)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}
