import SwiftUI
import WeatherCore

/// Single Today screen: compact hero, native section picker, original chart grammar.
struct TodayScreen: View {
    @Bindable var store: WeatherStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showingSearch = false
    @State private var showingSettings = false
    @State private var detailKind: ChartDetailSheet.Kind?
    @State private var section: TodaySection = .temperature
    @State private var showWetBulb = false
    @State private var scrubCoordinator = ActiveScrubCoordinator()

    enum TodaySection: String, CaseIterable, Identifiable {
        case temperature, rain, climate
        var id: String { rawValue }
        var title: String {
            switch self {
            case .temperature: return "Temperature"
            case .rain: return "Rain"
            case .climate: return "Climate"
            }
        }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    locationSidebar
                } detail: {
                    phoneStack
                }
            } else {
                phoneStack
            }
        }
        .environment(scrubCoordinator)
        .sheet(isPresented: $showingSearch) {
            SearchSheet(store: store) { result in
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

    private var phoneStack: some View {
        NavigationStack {
            content
                .navigationTitle("")
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .locating, .loading:
            VStack(spacing: 0) {
                chromeHeader(overAtmosphere: false)
                TodaySkeleton()
            }
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
                                formatter: store.formatter,
                                dateLine: store.dateLine
                            ) { panel in
                                jump(to: panel, proxy: proxy)
                            }
                        }
                        chromeHeader(overAtmosphere: true)
                    }
                    .id(ScrollAnchor.top)

                    VStack(alignment: .leading, spacing: 20) {
                        if let banner = store.banner {
                            BannerView(message: banner) { store.dismissBanner() }
                        }

                        Picker("Section", selection: $section) {
                            ForEach(TodaySection.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: section) { _, newValue in
                            if newValue == .temperature { store.ensureClimatology() }
                            if newValue == .rain { store.ensureYTD(); store.ensureClimatology() }
                            if newValue == .climate { store.ensureClimatology() }
                        }

                        panels

                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: sizeClass == .regular ? 720 : .infinity, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemBackground))
                }
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await store.refresh() }
            .onAppear {
                store.ensureClimatology()
                if store.heroBadges.contains(where: { $0.panel == .wetBulb }) {
                    showWetBulb = true
                }
            }
            .onChange(of: store.pendingPanelJump) { _, panel in
                guard let panel else { return }
                jump(to: panel, proxy: proxy)
                store.pendingPanelJump = nil
            }
            .onChange(of: store.heroBadges.map(\.panel)) { _, panels in
                if panels.contains(.wetBulb) { showWetBulb = true }
            }
        }
    }

    private enum ScrollAnchor: Hashable { case top }

    private func jump(to panel: PanelID, proxy: ScrollViewProxy) {
        switch panel {
        case .temperature:
            section = .temperature
        case .wetBulb:
            section = .temperature
            showWetBulb = true
        case .rain:
            section = .rain
            store.ensureYTD()
        case .climate:
            section = .climate
            store.ensureClimatology()
        }
        withAnimation {
            proxy.scrollTo(panel, anchor: .top)
        }
    }

    // MARK: - Chrome

    private func chromeHeader(overAtmosphere: Bool) -> some View {
        HStack(alignment: .center) {
            locationMenu
            Spacer(minLength: 8)
            if let location = store.location {
                Button {
                    store.toggleFavorite(location)
                } label: {
                    Image(systemName: store.isFavorite(location) ? "star.fill" : "star")
                        .font(.body.weight(.semibold))
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(store.isFavorite(location) ? "Remove from favorites" : "Add to favorites")
            }
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
        .foregroundStyle(Color.primary)
    }

    private var locationMenu: some View {
        Menu {
            if store.showsSourceToggle {
                Button {
                    Task { await store.switchSource(to: .geo) }
                } label: {
                    Label("My Location", systemImage: store.activeSource == .geo ? "checkmark" : "location.fill")
                }
                Button {
                    Task { await store.switchSource(to: .custom) }
                } label: {
                    Label(
                        store.customLocation?.shortName ?? "Saved place",
                        systemImage: store.activeSource == .custom ? "checkmark" : "building.2.fill")
                }
            }
            if !store.favoriteLocations.isEmpty {
                Section("Favorites") {
                    ForEach(store.favoriteLocations, id: \.cacheKey) { place in
                        Button {
                            Task { await store.loadFavorite(place) }
                        } label: {
                            Label(place.shortName, systemImage: "star.fill")
                        }
                    }
                }
            }
            Button {
                showingSearch = true
            } label: {
                Label("Search…", systemImage: "magnifyingglass")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.caption.weight(.semibold))
                Text(store.location?.name ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel("Location: \(store.location?.name ?? "not set")")
        .accessibilityHint("Choose a location or search")
    }

    private var locationSidebar: some View {
        List {
            Section("Favorites") {
                if store.favoriteLocations.isEmpty {
                    Text("Star a place to pin it here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.favoriteLocations, id: \.cacheKey) { place in
                    Button(place.name) {
                        Task { await store.loadFavorite(place) }
                    }
                }
            }
            Section("Recent") {
                ForEach(store.recentLocations, id: \.cacheKey) { place in
                    Button(place.name) {
                        Task { await store.loadFavorite(place) }
                    }
                }
            }
            Button {
                showingSearch = true
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
        }
        .navigationTitle("Places")
    }

    // MARK: - Panels

    @ViewBuilder
    private var panels: some View {
        let timeZone = store.locationTimeZone
        switch section {
        case .temperature:
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

            DisclosureGroup(isExpanded: $showWetBulb) {
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
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wet bulb")
                        .font(.headline)
                    Text("Feels-like heat stress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .id(PanelID.wetBulb)
            }
            .tint(.primary)

        case .rain:
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
                }
            }
            .onAppear { store.ensureYTD() }

        case .climate:
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
                }
            }
            .onAppear { store.ensureClimatology() }
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
