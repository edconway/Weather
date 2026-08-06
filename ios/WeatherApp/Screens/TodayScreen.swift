import SwiftUI
import WeatherCore

/// The single scrolling screen (§8.2). Charts arrive in Phase 4; the panel
/// scaffolding and the badge → panel scroll targets are wired up here.
struct TodayScreen: View {
    @Bindable var store: WeatherStore

    @State private var showingSearch = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("")
                .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showingSearch) {
            SearchSheet { result in
                Task { await store.selectSearchResult(result) }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(store: store)
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
                header
                ErrorView(message: message) {
                    Task { await store.retry() }
                }
            }
        case .searchFirst(let hint):
            VStack(spacing: 0) {
                header
                SearchFirstView(hint: hint) { showingSearch = true }
            }
        case .loaded:
            loadedScroll
        }
    }

    private var loadedScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                        .id(ScrollAnchor.top)

                    if let banner = store.banner {
                        BannerView(message: banner) { store.dismissBanner() }
                    }

                    if let conditions = store.conditions {
                        HeroView(
                            conditions: conditions,
                            badges: store.heroBadges,
                            formatter: store.formatter
                        ) { panel in
                            withAnimation { proxy.scrollTo(panel, anchor: .top) }
                        }
                    }

                    panels

                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await store.refresh() }
            .onChange(of: store.pendingPanelJump) { _, panel in
                guard let panel else { return }
                withAnimation { proxy.scrollTo(panel, anchor: .top) }
                store.pendingPanelJump = nil
            }
        }
    }

    private enum ScrollAnchor: Hashable { case top }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Button {
                    showingSearch = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(Palette.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.location?.name ?? "—")
                                .font(.title2.weight(.semibold))
                                .lineLimit(1)
                            if !store.dateLine.isEmpty {
                                Text(store.dateLine)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Location: \(store.location?.name ?? "not set")")
                .accessibilityHint("Search for a different location")

                Spacer(minLength: 8)

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            if store.showsSourceToggle {
                SourceToggle(
                    activeSource: store.activeSource,
                    customShortName: store.customLocation?.shortName ?? "Custom"
                ) { source in
                    Task { await store.switchSource(to: source) }
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Panels

    @ViewBuilder
    private var panels: some View {
        let timeZone = store.locationTimeZone

        PanelCard(
            id: .temperature, symbol: "thermometer.medium", title: "Temperature",
            hint: "Actual air temp, high & low", tint: Palette.temperature
        ) {
            ChartSlot(title: "48-Hour Temperature", subtitle: Subtitles.hourlyTemp(store)) {
                HourlyTempChart(
                    points: store.hourlyPoints, series: .temperature,
                    formatter: store.formatter, timeZone: timeZone)
            }
            ChartSlot(title: "14-Day Temperature", subtitle: Subtitles.dailyTemp(store)) {
                // The band needs climatology; the lines do not, so the chart
                // renders straight away and the grey band fills in behind it.
                DailyTempChart(
                    points: store.dailyPoints, series: .temperature,
                    formatter: store.formatter, timeZone: timeZone)
            }
        }
        // §1.4.7: the climatology fetch is triggered by this panel appearing,
        // replacing the web's IntersectionObserver.
        .onAppear { store.ensureClimatology() }

        PanelCard(
            id: .wetBulb, symbol: "humidity.fill", title: "Wet Bulb · Feels-Like Heat",
            hint: "Heat stress", tint: Palette.wetBulb
        ) {
            ChartSlot(title: "48-Hour Wet Bulb", subtitle: Subtitles.hourlyWetBulb(store)) {
                HourlyTempChart(
                    points: store.hourlyPoints, series: .wetBulb,
                    formatter: store.formatter, timeZone: timeZone)
            }
            ChartSlot(title: "14-Day Wet Bulb", subtitle: Subtitles.dailyWetBulb(store)) {
                DailyTempChart(
                    points: store.dailyPoints, series: .wetBulb,
                    formatter: store.formatter, timeZone: timeZone)
            }
        }

        PanelCard(
            id: .rain, symbol: "cloud.rain.fill", title: "Rain",
            hint: "Precipitation", tint: Palette.rain
        ) {
            ChartSlot(title: "48-Hour Rainfall", subtitle: Subtitles.hourlyRain(store)) {
                HourlyRainChart(
                    points: store.hourlyPoints,
                    formatter: store.formatter, timeZone: timeZone)
            }
            ChartSlot(title: "14-Day Rainfall", subtitle: Subtitles.dailyRain(store)) {
                DailyRainChart(
                    points: store.dailyPoints,
                    formatter: store.formatter, timeZone: timeZone)
            }
            ChartSlot(title: "Year-to-Date Rainfall", subtitle: Subtitles.ytdRain(store)) {
                if let series = store.ytdSeries {
                    YTDRainChart(
                        series: series, formatter: store.formatter,
                        thisYear: store.ytdRain?.thisYear ?? 0, timeZone: timeZone)
                } else {
                    ChartPlaceholder(message: "Loading year-to-date rainfall…")
                }
            }
            .onAppear { store.ensureYTD() }
        }

        PanelCard(
            id: .climate, symbol: "chart.bar.fill", title: "Climate Overview",
            hint: "Monthly normals", tint: Palette.accent
        ) {
            ChartSlot(title: "Climate Overview", subtitle: Subtitles.climate(store)) {
                if let climatology = store.climatology {
                    ClimateChart(
                        points: ChartSeries.climate(climatology),
                        formatter: store.formatter)
                } else {
                    ChartPlaceholder(message: "Loading climate data…")
                }
            }
        }
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

/// A titled chart section: `secHdr(title, details)` plus the chart itself.
private struct ChartSlot<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, subtitle: subtitle)
            content
        }
    }
}
