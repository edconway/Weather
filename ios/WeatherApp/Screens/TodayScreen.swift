import SwiftUI
import WeatherCore

/// The single scrolling screen (§8.2): atmosphere hero, native sections, charts.
struct TodayScreen: View {
    @Bindable var store: WeatherStore

    @State private var showingSearch = false
    @State private var showingSettings = false
    @State private var detailKind: ChartDetailSheet.Kind?
    /// Shared across every chart on this screen so scrubbing one clears
    /// whichever other chart's readout was pinned — see `StickyXSelection`.
    @State private var scrubCoordinator = ActiveScrubCoordinator()

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
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(store: store)
        }
        .sheet(item: $detailKind) { kind in
            ChartDetailSheet(kind: kind, store: store)
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .top) {
                        if let conditions = store.conditions {
                            HeroView(
                                conditions: conditions,
                                badges: store.heroBadges,
                                formatter: store.formatter
                            ) { panel in
                                withAnimation { proxy.scrollTo(panel, anchor: .top) }
                            }
                        }
                        chromeHeader(overAtmosphere: true)
                    }
                    .id(ScrollAnchor.top)

                    VStack(alignment: .leading, spacing: 22) {
                        if let banner = store.banner {
                            BannerView(message: banner) { store.dismissBanner() }
                        }

                        panelJump(proxy: proxy)

                        if store.showsSourceToggle {
                            SourceToggle(
                                activeSource: store.activeSource,
                                customShortName: store.customLocation?.shortName ?? "Custom"
                            ) { source in
                                Task { await store.switchSource(to: source) }
                            }
                        }

                        panels

                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await store.refresh() }
            .onChange(of: store.pendingPanelJump) { _, panel in
                guard let panel else { return }
                withAnimation { proxy.scrollTo(panel, anchor: .top) }
                store.pendingPanelJump = nil
            }
        }
    }

    private enum ScrollAnchor: Hashable { case top }

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

    private func panelJump(proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                jumpChip("Temp", panel: .temperature, proxy: proxy)
                jumpChip("Wet bulb", panel: .wetBulb, proxy: proxy)
                jumpChip("Rain", panel: .rain, proxy: proxy)
                jumpChip("Climate", panel: .climate, proxy: proxy)
            }
        }
        .accessibilityLabel("Jump to section")
    }

    private func jumpChip(_ title: String, panel: PanelID, proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation { proxy.scrollTo(panel, anchor: .top) }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Scrolls to the \(title.lowercased()) section")
    }

    // MARK: - Panels

    @ViewBuilder
    private var panels: some View {
        let timeZone = store.locationTimeZone

        WeatherSection(
            id: .temperature,
            title: "Temperature",
            caption: "Actual air temp, high & low"
        ) {
            HourlyTempChart(
                points: store.hourlyPoints, series: .temperature,
                formatter: store.formatter, timeZone: timeZone,
                detailText: Subtitles.hourlyTemp(store),
                onOpenDetail: { detailKind = .hourlyTemp })
            DailyTempChart(
                points: store.dailyPoints, series: .temperature,
                formatter: store.formatter, timeZone: timeZone,
                detailText: Subtitles.dailyTemp(store),
                onOpenDetail: { detailKind = .dailyTemp })
        }
        .onAppear {
            // Kick off the slow archive fetches as soon as the first panel is
            // on screen, so YTD/climate aren't still spinning when the user
            // reaches the bottom.
            store.ensureClimatology()
            store.ensureYTD()
        }

        WeatherSection(
            id: .wetBulb,
            title: "Wet Bulb",
            caption: "Feels-like heat stress"
        ) {
            HourlyTempChart(
                points: store.hourlyPoints, series: .wetBulb,
                formatter: store.formatter, timeZone: timeZone,
                detailText: Subtitles.hourlyWetBulb(store),
                onOpenDetail: { detailKind = .hourlyWetBulb })
            DailyTempChart(
                points: store.dailyPoints, series: .wetBulb,
                formatter: store.formatter, timeZone: timeZone,
                detailText: Subtitles.dailyWetBulb(store),
                onOpenDetail: { detailKind = .dailyWetBulb })
        }

        WeatherSection(
            id: .rain,
            title: "Rain",
            caption: "Precipitation"
        ) {
            HourlyRainChart(
                points: store.hourlyPoints,
                formatter: store.formatter, timeZone: timeZone,
                detailText: Subtitles.hourlyRain(store),
                onOpenDetail: { detailKind = .hourlyRain })
            DailyRainChart(
                points: store.dailyPoints,
                formatter: store.formatter, timeZone: timeZone,
                detailText: Subtitles.dailyRain(store),
                onOpenDetail: { detailKind = .dailyRain })
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
        .onAppear { store.ensureClimatology() }
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
