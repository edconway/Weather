# iOS + watchOS Port — Implementation Plan

This document is the complete specification for porting the Weather web app (this repo) to a native iOS app with a watchOS companion app and watch-face complications. It is written to be executed **phase by phase, in order**, by an implementing agent. Everything needed — API contracts, formulas, thresholds, mappings, file layout, and acceptance criteria — is spelled out here or in the referenced web-app source files (`app.js`, `charts.js`, `search.js`).

---

## 0. Ground rules for the implementing agent

1. **Work through the phases in order.** Do not start a phase until the previous phase's acceptance criteria pass. Each phase ends with a buildable, runnable state.
2. **Do not invent behavior.** Where this doc says "port X from `app.js`", open `app.js` and replicate the arithmetic exactly (thresholds, rounding, fallbacks). The web app is the reference implementation. Deviations are listed explicitly in §1.4 — there are no others.
3. **Prefer boring, well-documented APIs**: SwiftUI, Swift Charts, WidgetKit, CoreLocation, URLSession, Codable, UserDefaults. No third-party dependencies. No Combine (use async/await). No UIKit except where unavoidable.
4. **All weather math lives in the shared package (`WeatherCore`)**, covered by unit tests with fixture JSON. UI targets contain no computation beyond layout.
5. **Build and run after every phase.** Use `xcodebuild` (see §12) and the iOS/watchOS simulators to verify. If a simulator screenshot tool is available, verify screens visually.
6. When something in this doc conflicts with reality (API field renamed, SDK deprecation), fix it the obvious way and leave a `// PLAN DEVIATION:` comment explaining what changed and why.

---

## 1. What we are building

### 1.1 The source app, in one paragraph

A client-side weather app using the free, keyless Open-Meteo APIs. Its differentiator is **historical context**: every current number is compared to normals computed from 5–10+ years of archive data. Features: geolocation + city search with a two-location toggle (GPS vs. searched); a hero panel (current temp, condition, feels-like, hi/lo, three tappable anomaly badges, rain/wind/UV stat tiles); eight charts (48-h temp, 14-day temp, 48-h wet bulb, 14-day wet bulb, 48-h rain, 14-day rain, YTD cumulative rain, monthly climate normals); metric/imperial toggle; dark/light/auto theme; persisted preferences.

### 1.2 Deliverables

| Target | Contents |
|---|---|
| **iOS app** (iOS 17+) | Full feature port: hero, badges, stat tiles, all 8 charts, search, two-location toggle, settings |
| **watchOS app** (watchOS 10+) | Cut-down: Now page, Hourly page, Daily page; anomaly badge; own location or phone-synced |
| **watchOS widget extension** | Complications: accessoryCircular, accessoryCorner, accessoryInline, accessoryRectangular |
| **iOS widget extension** (Phase 8, optional) | Lock-screen accessories (reuse watch views) + systemSmall/systemMedium home-screen widgets |
| **WeatherCore** (local Swift Package) | Models, API clients, throttling, caching, all derived-data math, formatting, WMO mapping, shared widget views |

### 1.3 Architectural decisions (final — do not re-litigate)

- **Native SwiftUI**, not a WKWebView wrapper. Complications and honest watch UX require native.
- **Minimum targets: iOS 17.0, watchOS 10.0.** Enables `@Observable`, `chartXSelection`, modern WidgetKit, `.backgroundTask` scene modifier.
- **Swift 6 compiler, Swift 5 language mode** (`SWIFT_VERSION = 5`) to keep concurrency friction low. `WeatherCore` public types that cross concurrency boundaries should be `Sendable` structs.
- **MVVM-lite**: one `@Observable` store per screen-ish area, plain structs everywhere else. No routers, no protocols-for-testability beyond what tests actually need.
- **Data source stays Open-Meteo** (forecast, archive, geocoding). Reverse geocoding switches from Nominatim to **CLGeocoder** (better on-platform, avoids Nominatim usage policy). Keep a Nominatim fallback only if CLGeocoder fails, with the same User-Agent string as the web app.
- **The watch fetches its own forecast directly** (URLSession works on watchOS). Heavy archive-derived data (normals) is computed on the phone and pushed to the watch via WatchConnectivity as a small derived blob. The watch never calls the archive API.
- **App Group** shared between each app and *its own* widget extension for cache + prefs. Note: App Groups do **not** span iPhone↔Watch; that's what WatchConnectivity is for.
- Working name/bundle IDs (user can rename later): app `com.edconway.weatherscope`, group `group.com.edconway.weatherscope`. Display name placeholder: **"WeatherScope"**. Do not ship the name "Weather" (collides with Apple's app).

### 1.4 Deliberate deviations from the web app (complete list)

1. **Current condition icon/label uses the *hourly* `weather_code` at the current hour** (fallback: daily code), instead of the web's daily code. Better for "now" and for complications. Add `weather_code` — already present — and **add `is_day` to the hourly request** for day/night icon variants.
2. **"Now" is computed in the forecast location's timezone** (from the API's `timezone`/`utc_offset_seconds` response fields), not the device timezone. The web app uses browser-local time, which is subtly wrong for remote searched locations. All "find today's index / current hour index" logic must use location-local wall time.
3. **Emoji icons → SF Symbols** (full mapping in §5.2).
4. **Theme**: system dark/light with an optional in-app override (System/Light/Dark). Drop the time-of-day ambience tinting (web `applyTimeAmbience`) — nonessential.
5. **Units default from locale** (`Locale.current.measurementSystem == .us` ⇒ imperial) instead of defaulting to metric. Toggle persists like the web.
6. **Tooltips → Swift Charts scrubbing** via `chartXSelection` + annotation popover, replacing DOM tooltip code.
7. **Lazy loading**: IntersectionObserver is replaced by `onAppear` of the relevant panel views inside a `LazyVStack` (same effect: climatology loads when the temp panel appears, YTD when the YTD chart approaches).
8. **Dual-axis climate chart** (temp lines + rain bars) becomes **two vertically stacked charts sharing the month x-axis** (Swift Charts has no dual y-axis).

---

## 2. Repository & project layout

Create everything under a new `ios/` directory in this repo:

```
ios/
├── WeatherScope.xcodeproj
├── WeatherCore/                          # local Swift Package (referenced by all targets)
│   ├── Package.swift
│   ├── Sources/WeatherCore/
│   │   ├── Models/
│   │   │   ├── ForecastResponse.swift    # Codable for /v1/forecast
│   │   │   ├── ArchiveResponse.swift     # Codable for /v1/archive
│   │   │   ├── GeocodingResponse.swift   # Codable for geocoding search
│   │   │   ├── WeatherLocation.swift     # lat, lon, name, source (geo|custom)
│   │   │   ├── WMOCode.swift             # §5
│   │   │   └── DerivedModels.swift       # Climatology, TempBand, DailyRainNormal,
│   │   │                                 # HourlyNormals, YTDRain, Anomaly, WatchSyncPayload
│   │   ├── API/
│   │   │   ├── OpenMeteoClient.swift     # forecast + geocoding, §4.1/§4.3
│   │   │   ├── ArchiveClient.swift       # archive calls THROUGH the throttler, §4.2
│   │   │   ├── ArchiveThrottler.swift    # actor: max 3 concurrent, 429 backoff, §4.4
│   │   │   └── ReverseGeocoder.swift     # CLGeocoder wrapper (+ Nominatim fallback)
│   │   ├── Logic/
│   │   │   ├── ClimatologyBuilder.swift  # §6.3
│   │   │   ├── TempBandDeriver.swift     # §6.4
│   │   │   ├── DailyRainDeriver.swift    # §6.5
│   │   │   ├── HourlyNormalsBuilder.swift# §6.6
│   │   │   ├── YTDRainBuilder.swift      # §6.7
│   │   │   ├── AnomalyEngine.swift       # §6.8
│   │   │   ├── CurrentConditions.swift   # §6.2 (now-index logic, hero numbers)
│   │   │   └── MMDD.swift                # mmdd distance helper, §6.1
│   │   ├── Cache/
│   │   │   ├── DiskCache.swift           # JSON file cache in App Group container, §7
│   │   │   └── WeatherRepository.swift   # orchestrates fetch-or-cache for everything
│   │   ├── Formatting/
│   │   │   └── UnitFormatter.swift       # §5.3
│   │   └── Prefs/
│   │       └── Prefs.swift               # UserDefaults(suiteName: appGroup), §7.3
│   └── Tests/WeatherCoreTests/
│       ├── Fixtures/                     # snapshot JSON, §11.1
│       └── *.swift
├── WeatherApp/                           # iOS app target
│   ├── WeatherScopeApp.swift
│   ├── Screens/ (TodayScreen, SearchSheet, SettingsSheet)
│   ├── Components/ (HeroView, AnomalyBadge, StatTile, PanelCard, SourceToggle, ErrorView, LoadingView)
│   ├── Charts/ (HourlyTempChart, DailyTempChart, HourlyWetBulbChart, DailyWetBulbChart,
│   │            HourlyRainChart, DailyRainChart, YTDRainChart, ClimateChart)
│   ├── Location/ (LocationProvider.swift)
│   ├── Store/ (WeatherStore.swift)
│   └── Sync/ (PhoneSessionManager.swift)   # WatchConnectivity, phone side
├── WeatherWatch/                         # watchOS app target
│   ├── WeatherWatchApp.swift
│   ├── Views/ (NowPage, HourlyPage, DailyPage)
│   ├── Store/ (WatchStore.swift)
│   └── Sync/ (WatchSessionManager.swift)   # WatchConnectivity, watch side
├── WeatherWatchWidgets/                  # watchOS widget extension (complications)
│   ├── WatchWidgetBundle.swift
│   ├── Providers/ (WeatherTimelineProvider.swift)
│   └── Widgets/ (CurrentConditionsWidget, TempAnomalyWidget, RainChanceWidget)
└── WeatherWidgets/                       # iOS widget extension (Phase 8)
```

**Targets & capabilities**

| Target | Bundle ID | Capabilities |
|---|---|---|
| WeatherApp | `com.edconway.weatherscope` | App Groups, Location When-In-Use, Background Modes (fetch) |
| WeatherWatch | `com.edconway.weatherscope.watchkitapp` | App Groups, Location When-In-Use |
| WeatherWatchWidgets | `com.edconway.weatherscope.watchkitapp.widgets` | App Groups |
| WeatherWidgets | `com.edconway.weatherscope.widgets` | App Groups, Location (optional) |

All targets use the single App Group `group.com.edconway.weatherscope`. Info.plist strings required: `NSLocationWhenInUseUsageDescription` ("Used to show weather and historical context for where you are. Never leaves your device except as coordinates sent to the weather API."). iOS app also needs `BGTaskSchedulerPermittedIdentifiers` = [`com.edconway.weatherscope.refresh`]. Add a `PrivacyInfo.xcprivacy` to each target declaring UserDefaults use (reason `CA92.1`); no tracking, no required-reason network APIs beyond defaults.

---

## 3. Phases and acceptance criteria (master roadmap)

### Phase 0 — Scaffolding
Create the Xcode project, all targets, the `WeatherCore` package, App Group entitlements, Info.plist strings. Stub views that just say "Hello" on iOS and watch. A stub complication that shows a static "—°".
**Done when:** `xcodebuild` succeeds for iOS app (+watch app embedded); both simulators show the stub UI; stub complication can be added to a watch face in the simulator.

### Phase 1 — Models + API clients (WeatherCore)
Codable models for the three API responses (§4), `OpenMeteoClient`, `ArchiveClient`, `ArchiveThrottler`, `ReverseGeocoder`. Record fixture JSON (§11.1).
**Done when:** unit tests decode all fixtures; a throttler test proves ≤3 concurrent and backoff sequencing (use a mock `URLProtocol`); a live smoke test (skipped in CI) fetches a real forecast for 51.5,-0.12.

### Phase 2 — Derived-data logic (WeatherCore)
Port every formula in §6 with unit tests pinned to fixture-derived expected values. Implement `DiskCache`, `Prefs`, `WeatherRepository` with TTLs from §7.
**Done when:** tests cover: today-index resolution across timezones; mmdd wrap-around (Dec 30 ↔ Jan 2); each anomaly threshold branch (write one test per branch of §6.8); YTD cumulative math; climatology monthly means; cache TTL expiry (injected clock).

### Phase 3 — iOS app: core screens, no charts
`WeatherStore` boot flow (§8.1), `LocationProvider`, hero panel with real data (temp, condition, feels-like, hi/lo, three anomaly badges, three stat tiles), search sheet (§8.3), two-location source toggle, settings sheet (units, theme override, about/attribution), loading/error/search-first states.
**Done when:** app runs on simulator; denying location lands on search-first state; searching "Paris" loads weather; toggle between GPS and custom location works and persists across relaunch; unit toggle updates every visible number.

### Phase 4 — iOS charts
All 8 charts per §8.4, in panel cards with headers/subtitles mirroring the web layout, scrubbing via `chartXSelection`, lazy loading of climatology/YTD on panel appear.
**Done when:** every chart renders with live data for two very different locations (e.g. London and Singapore); scrubbing shows correct values incl. "actual vs forecast" tagging; historical overlays appear after archive data loads (progressive render, no blocking).

### Phase 5 — watchOS app
Three pages (§9), watch's own location flow, direct forecast fetch, normals via WatchConnectivity with graceful "no context yet" fallback, units synced from phone prefs (plus local toggle).
**Done when:** watch simulator shows real forecast; with the paired-phone simulator running, anomaly badge appears after sync; without sync it shows the no-context fallback cleanly.

### Phase 6 — Complications
Three widgets × families per §10, timeline provider reading the shared cache, refresh strategy, `widgetURL` deep links.
**Done when:** all families render in the widget gallery and on a face; values match the watch app; timeline snapshot test passes; tapping opens the watch app.

### Phase 7 — Background refresh + sync hardening
iOS `BGAppRefreshTask` (§7.4), watch `.backgroundTask(.appRefresh)`, `WidgetCenter.reloadTimelines` after fresh data, WatchConnectivity retry/queue behavior.
**Done when:** simulated background refresh (see §7.4 for the debugger trick) updates cache and reloads timelines; killing and relaunching apps never shows stale-location data mismatches.

### Phase 8 (optional) — iOS widgets + polish
Lock-screen accessories reusing §10 views; systemSmall/Medium hero widget; accessibility pass (§8.5); App Store prep checklist (§13).

---

## 4. API contracts (exact)

All requests are HTTPS GET, JSON responses, **no API keys**. Base hosts:
- Forecast: `https://api.open-meteo.com/v1/forecast`
- Archive: `https://archive-api.open-meteo.com/v1/archive`
- Geocoding search: `https://geocoding-api.open-meteo.com/v1/search`

### 4.1 Forecast request (port of `getForecast` in app.js)

```
latitude={lat}&longitude={lon}&timezone=auto
&forecast_days=7&past_days=7
&daily=weather_code,temperature_2m_max,temperature_2m_min,wet_bulb_temperature_2m_max,wet_bulb_temperature_2m_min,apparent_temperature_max,precipitation_sum,precipitation_probability_max,wind_speed_10m_max,uv_index_max
&past_hours=24&forecast_hours=48
&hourly=temperature_2m,wet_bulb_temperature_2m,apparent_temperature,precipitation,precipitation_probability,rain,showers,snowfall,weather_code,is_day
```

(`is_day` is the one addition vs. the web app — see §1.4.1.)

Response shape (fields actually used): top-level `timezone` (e.g. `"Europe/London"`), `utc_offset_seconds`; `daily.time: [String]` (`"YYYY-MM-DD"`, location-local); each daily variable as `[Double?]` (`weather_code` as `[Int?]`); `hourly.time: [String]` (`"YYYY-MM-DDTHH:mm"`, location-local, **no timezone suffix**); hourly variables as `[Double?]`/`[Int?]`.

**Decode all value arrays as optional-element arrays.** Open-Meteo returns `null` for missing values.

**Keep the time strings as strings.** All index-finding is done by string comparison against strings built from "now in the location's timezone" (§6.2), exactly like the web app. Do not parse them into `Date` for indexing (only for display formatting, and then always with the location's `TimeZone`).

### 4.2 Archive requests (all go through the throttler)

Three distinct archive calls, ported 1:1:

**(a) Climatology — 10 years daily** (port of `getClimatology`): one request.
```
latitude&longitude&timezone=auto
&start_date={thisYear-10}-01-01&end_date={thisYear-1}-12-31
&daily=temperature_2m_max,temperature_2m_min,wet_bulb_temperature_2m_max,wet_bulb_temperature_2m_min,precipitation_sum
```

**(b) Hourly normals — 5 requests, one per year i=1…5** (port of `getHourlyNormals`): window is (today − 7 days) … (today + 7 days) in year `thisYear − i`.
```
latitude&longitude&timezone=auto
&start_date={windowStart}&end_date={windowEnd}
&hourly=temperature_2m,wet_bulb_temperature_2m,precipitation
```

**(c) YTD rain — 1 big request** (port of `getRainYTD`):
```
latitude&longitude&timezone=auto
&start_date=2000-01-01&end_date={today}
&daily=precipitation_sum
```

### 4.3 Geocoding search (port of `doSearch`)

```
name={query}&count=6&language=en&format=json
```
Results: `results: [{name, latitude, longitude, admin1?, country?, country_code?}]`. Display name = `name + (", " + admin1)? + (", " + country)?` — same as web. Debounce input 300 ms in the UI.

### 4.4 Archive throttler (port of `archiveFetch`/`_drainArchive`)

An `actor ArchiveThrottler` wrapping URLSession:
- Max **3** concurrent archive requests; extra callers await in FIFO order.
- On HTTP **429** with `tries < 4`: retry after `0.4 * 2^tries` seconds, i.e. **0.8 s, 1.6 s, 3.2 s, 6.4 s**, requeued at the **front**.
- After 4 retries, return the 429 response as an error.
- Only archive calls use the throttler; forecast/geocoding go direct.

---

## 5. Mappings & formatting

### 5.1 WMO code → label (port of `WMO` + `wmo()` in app.js, keep labels identical)

Fallback rule: unknown code → try `(code/10)*10` (integer division) → else "Unknown".

### 5.2 WMO code → SF Symbol (new; use exactly this table)

| Codes | Label (from web) | SF Symbol (day) | SF Symbol (night) |
|---|---|---|---|
| 0 | Clear Sky | `sun.max.fill` | `moon.stars.fill` |
| 1 | Mainly Clear | `sun.max.fill` | `moon.stars.fill` |
| 2 | Partly Cloudy | `cloud.sun.fill` | `cloud.moon.fill` |
| 3 | Overcast | `cloud.fill` | `cloud.fill` |
| 45, 48 | Foggy / Icy Fog | `cloud.fog.fill` | `cloud.fog.fill` |
| 51, 53, 55 | Drizzle family | `cloud.drizzle.fill` | `cloud.drizzle.fill` |
| 56, 57 | Freezing Drizzle | `cloud.sleet.fill` | `cloud.sleet.fill` |
| 61, 63 | Light Rain / Rain | `cloud.rain.fill` | `cloud.rain.fill` |
| 65 | Heavy Rain | `cloud.heavyrain.fill` | `cloud.heavyrain.fill` |
| 66, 67 | Freezing Rain | `cloud.sleet.fill` | `cloud.sleet.fill` |
| 71, 73, 75, 77 | Snow family | `cloud.snow.fill` | `cloud.snow.fill` |
| 80 | Light Showers | `cloud.sun.rain.fill` | `cloud.moon.rain.fill` |
| 81 | Showers | `cloud.rain.fill` | `cloud.rain.fill` |
| 82 | Heavy Showers | `cloud.heavyrain.fill` | `cloud.heavyrain.fill` |
| 85, 86 | Snow Showers | `cloud.snow.fill` | `cloud.snow.fill` |
| 95 | Thunderstorm | `cloud.bolt.fill` | `cloud.bolt.fill` |
| 96, 99 | Thunderstorm & Hail | `cloud.bolt.rain.fill` | `cloud.bolt.rain.fill` |

Render with `.symbolRenderingMode(.multicolor)`. Day/night chosen from hourly `is_day` at the current hour (default day when unavailable).

### 5.3 Units (port of the `imp` helpers)

Store everything internally in **metric** (°C, km/h, mm) — as the API returns it — and convert at display time only. Port: `c2f = c*9/5+32`, `kmh→mph = *0.621371`, `mm→in = *0.0393701`. Formatting rules (match web): temps rounded to integers with `°C`/`°F`; wind rounded integer `km/h`/`mph`; precip metric `x.x mm` (1 dp), imperial `x.xx"` (2 dp). UV label: `≤2 Low, ≤5 Moderate, ≤7 High, ≤10 Very High, else Extreme`, shown as `"{value, 1dp} {label}"`.

---

## 6. Derived-data formulas (the heart of the app — port precisely)

All functions below live in `WeatherCore/Logic` and are pure (inputs → outputs, injected `now` and `TimeZone` for testability).

### 6.1 `mmddDist(_ a: String, _ b: String) -> Int` (port of `_mmddDist`)

Distance in calendar days between two `"MM-DD"` strings, computed in a fixed leap year (2020), wrapped: if `d > 182` subtract 365; if `d < -182` add 365; return `abs`. Used for the ±3-day windows below.

### 6.2 Current conditions (port of the top of `renderContent`)

Given a forecast response and `now` in the **location's timezone**:
- `todayStr = "YYYY-MM-DD"` of now (location-local). `t0 = max(0, daily.time.firstIndex(of: todayStr))` — with `past_days=7` this is normally 7, but **always find it by string match**, never hardcode.
- `nowHourStr = "\(todayStr)T\(HH):00"` (current hour, zero-padded). `nowIdx = max(0, hourly.time.firstIndex(where: { $0 >= nowHourStr }))` (lexicographic compare works on ISO strings).
- Hero numbers: `tNow = hourly.temperature_2m[nowIdx] ?? daily.temperature_2m_max[t0]`; `feelsLike = hourly.apparent_temperature[nowIdx] ?? daily.apparent_temperature_max[t0]`; `hi/lo = daily max/min at t0`; `rainChance = daily.precipitation_probability_max[t0]`; `wind = daily.wind_speed_10m_max[t0]`; `uv = daily.uv_index_max[t0]`; condition code = `hourly.weather_code[nowIdx] ?? daily.weather_code[t0]` (deviation §1.4.1).

### 6.3 Climatology (port of `getClimatology`)

From the 10-year daily archive response build:
- `byMonthYear["YYYY-MM"] = {tMax: [Double], tMin: [Double], rainTotal: Double}` — per month-of-a-specific-year: collect daily maxes/mins, **sum** daily precipitation.
- `months[0...11]`: for each calendar month, average the per-year month means of tMax and tMin, and average the per-year month rain **totals**. (Two-level averaging — do not flatten all days into one pool.)
- `byMMDD["MM-DD"] = {maxes, mins, wbMaxes, wbMins, rains}` — flat pools of every year's value for that calendar day.
- Keep `yearStart = thisYear-10`, `yearEnd = thisYear-1` for chart subtitles.

### 6.4 14-day temp band (port of `deriveTempBand`)

For day offsets `i in -7...6` from today: `mmdd` of that date; pool every `byMMDD` entry whose `mmddDist ≤ 3`; `dailyAvg[i+7] = {tMax: avg(maxes), tMin: avg(mins), wbMax: avg(wbMaxes), wbMin: avg(wbMins)}`. Today's normal is `dailyAvg[7]`.

### 6.5 Daily rain normals (port of `deriveDailyRain` + `classifyRain`)

For each of the 7 forecast dates (daily indices `t0 ... t0+6`): pool `byMMDD` rains within `mmddDist ≤ 3`; compute `histMeanMm` (mean), `histMedianMm`, `wetDayProbability` (share of pooled days ≥ 0.1 mm), `p90Mm` (sorted, index `floor(n*0.9)`). Pair with `forecastMm = daily.precipitation_sum[i]` and `probabilityMax`.
Classification chips (exact thresholds from `classifyRain`): forecast < 0.1 → **Dry**; `p90 > 0 && forecast ≥ p90` → **Heavy**; `forecast > mean*1.5 && forecast-mean ≥ 1` → **Wetter**; `mean > 0.5 && forecast < mean*0.5` → **Drier**; else **Near avg**.

### 6.6 Hourly normals (port of `getHourlyNormals`)

Across the 5 yearly archive windows: bucket every hourly sample by hour-of-day (`Int(time[11..13])`, 0–23). Outputs: `temp.avgByHour[24]`, `wetBulb.avgByHour[24]`, `rain.avgByHour[24]` (missing → 0 for rain, nil for temps), `rain.wetHourProbabilityByHour` (share ≥ 0.1 mm), `rain.p90ByHour` (per-hour sorted p90). Year range `thisYear-5 … thisYear-1`.

### 6.7 YTD cumulative rain (port of `getRainYTD`)

From the 2000→today daily archive: group `byYear[year]["MM-DD"] = precip ?? 0`. Labels = every `"MM-DD"` from Jan 1 of this year through today. `cumCurrentYear` = running sum of this year's values over labels (missing day = 0). For each historical year (2000 ≤ y < thisYear) compute its running cumulative over the same labels; `cumHistAvg[i]` = mean across years at index i. `latestDate` = last archive date ≤ today **that actually has data** (the archive lags ~2–5 days — this is why the current-year line can end before today). Forecast extension: starting from `cumHistAvg.last`, add the historical mean daily rain for each of the next up-to-7 calendar dates (stop at year end) → `cumHistAvgExt`. Also build the current-year **projection**: from the last actual cumulative value, add forecast daily `precipitation_sum` for days after `latestDate` (the web chart draws this dashed — see `makeRainYTDChart` in charts.js).

### 6.8 Anomaly badges (port of `_tempAnomaly`, `_rainAnomaly`, `_wbAnomaly` — exact thresholds)

All computed in °C/mm, display-converted afterward.

**Temperature** (needs `dailyAvg[7]` from §6.4): `delta = (hi+lo)/2 − (histMax+histMin)/2`. `|delta| < 1` → "Near normal" (neutral). Else text `"{round(|delta| in user units)}°(F|C) warmer|colder than normal"`, kind warm/cold. Note the web converts the *delta* by scale only (`*9/5`, no +32) — a delta is a difference, do the same.

**Rain** (needs §6.5 entry for today, index 0): forecast < 0.1 → mean ≥ 1 ? "Drier than normal" (dry) : "Dry day expected" (dry); `p90>0 && forecast ≥ p90` → "Unusually wet" (wet); `forecast > mean*1.5 && diff ≥ 1` → "Wetter than normal" (wet); `mean > 0.5 && forecast < mean*0.5` → "Drier than normal" (dry); else "Near normal rainfall" (neutral).

**Mugginess** (needs hourly wet bulb + §6.6 or §6.4 fallback): `wbNow = hourly.wet_bulb_temperature_2m[nowIdx]`; `wbNorm = wetBulb.avgByHour[currentHour]`, fallback `(dailyAvg[7].wbMax + wbMin)/2`. **Suppress the badge entirely if `wbNow` or `wbNorm` is nil or `wbNorm < 8`** (°C — badge is meaningless in cool weather). `pct = round((wbNow−wbNorm)/wbNorm*100)`. `|pct| < 5` → "Near normal mugginess"; else `"Feels {|pct|}% more|less muggy than usual"`.

Badges are **progressive**: hero renders immediately from the forecast; badges appear when their archive-derived inputs arrive (Rain + Temp need climatology; Mugginess prefers hourly normals). Tapping a badge scrolls to its panel (temp → temperature panel, mugginess → wet bulb panel, rain → rain panel), mirroring the web's `data-panel-jump` — use `ScrollViewReader`.

---

## 7. Caching, persistence, refresh

### 7.1 Cache keys and TTLs

`DiskCache` writes Codable JSON files to `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`/`Caches/`. Key = `{kind}-{lat}-{lon}` with lat/lon rounded to **2 decimals** (~1 km — prevents GPS jitter from busting the cache). Each entry stores `savedAt`; expiry checked on read with an injectable clock.

| Kind | TTL | Notes |
|---|---|---|
| `forecast` | 15 min | Also serve-stale-while-revalidate up to 3 h if network fails |
| `hourlyNormals` | 7 days | Derived output only (arrays of 24), not raw responses |
| `climatology` | 30 days | Store derived `months` + `byMMDD` (the raw 10-yr response is ~1 MB; the derived blob is small) |
| `ytdRain` | 24 h | Store derived arrays |
| `lastLocation` | none | Last successfully-loaded location; used by widgets & cold start |

### 7.2 Repository behavior (mirrors the web's load sequence)

`WeatherRepository.load(location:)`:
1. Forecast (network or cache) → publish immediately (hero + forecast-only charts render).
2. Kick off in parallel, each updating state as it lands: hourly normals (§6.6), climatology → temp band + daily rain normals (§6.3–6.5).
3. YTD (§6.7) is **lazy** — only when the YTD chart scrolls near (or on watch: never).
4. On location switch, cancel in-flight tasks and reset derived state (mirror `resetWeatherData`/`resetLazyState` and the web's stale-response guard: check the location key before applying results).

### 7.3 Preferences (port of localStorage prefs)

`UserDefaults(suiteName: appGroup)`, keys: `imperial: Bool` (default from locale), `theme: String` (`system|light|dark`), `activeSource: String` (`geo|custom`), `customLat/customLon/customName`, plus `lastGeoLat/lastGeoLon/lastGeoName`. Same restore-on-boot semantics as the web (§8.1).

### 7.4 Background refresh

- **iOS**: `BGAppRefreshTask` id `com.edconway.weatherscope.refresh`, scheduled ~every 30–60 min. Handler: refresh forecast for the active location into the shared cache, then `WidgetCenter.shared.reloadAllTimelines()`. Debug trigger in lldb: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.edconway.weatherscope.refresh"]`.
- **watchOS**: `.backgroundTask(.appRefresh)` + `WKApplicationRefreshBackgroundTask` rescheduling every ~30 min; same refresh-then-reload-timelines flow.
- Widgets also self-serve: the timeline provider fetches if cache is stale (§10.3), so complications survive even if apps never run.

---

## 8. iOS app spec

### 8.1 Boot flow (port of `init()` in app.js)

1. If `activeSource == custom` and a custom location is saved → load it directly (no location prompt).
2. Else request when-in-use location (timeout 15 s, accept cached fix ≤ 5 min old — mirror the web's `maximumAge`); reverse-geocode to "City, Region" via CLGeocoder; load weather.
3. Location denied/failed and no data → **search-first state** (message + auto-focused search field, port of `showSearchFirst`).
4. Errors after data exists → non-blocking banner; errors before → full-screen error with Try Again (port of `showErr`).

### 8.2 Today screen layout (single scroll view, mirrors the web order)

1. **Header**: location name (tap → search sheet), date line, source toggle capsule ("My Location" / short custom name — only when both exist, port of the `src-toggle` logic), settings gear.
2. **Hero card**: big temp + condition symbol, condition label, "Feels like X · ↑hi / ↓lo", up to three anomaly badges (§6.8), three stat tiles (Rain chance %, Wind, UV with label).
3. **Temperature panel** (red cap "Temperature — Actual air temp, high & low"): 48-Hour chart, 14-Day chart.
4. **Wet Bulb panel** (teal cap "Wet Bulb · Feels-Like Heat — Heat stress"): 48-Hour, 14-Day.
5. **Rain panel** (blue cap): 48-Hour, 14-Day, Year-to-Date.
6. **Climate Overview panel**: monthly normals (stacked pair, §8.4.8).
7. **Footer**: "Forecast & historical data from Open-Meteo" attribution (required — §13).

Panel caps + chart subtitles replicate the web's wording (see `renderContent` for the subtitle templates — they include location short-name and the historical year ranges).

### 8.3 Search (port of search.js)

Sheet with a text field (auto-focused), 300 ms debounce, ≥1 char, Open-Meteo geocoding (§4.3), rows: name + "admin1, CC" detail. Selection: save as custom location, set `activeSource = custom`, dismiss, load. Handle: empty results ("No results for …"), network failure ("Search failed — check your connection.").

### 8.4 Charts (Swift Charts; one view per chart, all take pre-derived data structs)

Shared conventions: x-scrub via `chartXSelection` with an annotation card showing the same fields as the web tooltips (`showTT` in app.js is the reference — including the "· actual"/"· forecast" tags); a vertical `RuleMark` at "now"/"today"; past segments full-opacity ("actual"), future dashed or 60 % opacity ("forecast"); historical overlays in gray.

1. **HourlyTempChart** (72 pts: 24 past + 48 forecast): temp `LineMark` (solid ≤ now, then dashed), 5-yr avg-by-hour `LineMark` gray dashed (map §6.6 `avgByHour` onto each timestamp's hour), now `RuleMark`. Scrub: time, temp, 5-yr avg.
2. **DailyTempChart** (14 days): hi `LineMark` red + lo `LineMark` blue; historical band `AreaMark` between `dailyAvg[i].tMin…tMax` (gray, 25 % opacity); today `RuleMark`. Scrub: day, high, low, hist range.
3/4. **Wet bulb variants** of 1/2 using `wet_bulb_*` fields and `wbMax/wbMin` band.
5. **HourlyRainChart** (72 slots): `BarMark` precip mm; probability shown in the scrub annotation only (no dual axis). Wet-hour p90 from §6.6 available in annotation ("heavier than 9 of 10 similar hours") — optional flourish, skip if fiddly.
6. **DailyRainChart** (14 days): `BarMark`; past bars gray-blue ("actual"), future bars accent ("forecast"); classification chip (§6.5) under each future bar or in the annotation.
7. **YTDRainChart**: current-year cumulative `LineMark` + soft `AreaMark`; historical-avg cumulative gray `LineMark`; dashed projection segment from `latestDate` using forecast sums; dashed gray extension `cumHistAvgExt`. Subtitle notes the "through {latestDate}" lag. This is the heaviest chart (~220–365 pts × 2 lines) — thin to every 2nd point if scrolling stutters.
8. **ClimateChart**: two stacked charts sharing month labels: top = avg-high/avg-low `LineMark`s; bottom = avg monthly rainfall `BarMark`s. Scrub selects a month across both.

### 8.5 Accessibility

Dynamic Type throughout; charts get `accessibilityLabel` matching the web's aria-labels and `accessibilityChartDescriptor` (AudioGraph) for at least the two temperature charts; badges are buttons with hints ("Shows the wet bulb panel").

---

## 9. watchOS app spec

Vertical `TabView` (watchOS 10 pagination), three pages. Data: forecast fetched directly (§4.1 — same request; it's ~100 KB, fine on watch); normals from phone sync (§9.2); prefs synced.

1. **NowPage**: location name (small), condition symbol, big temp, "↑hi ↓lo", feels-like, one line of stat glyphs (rain % · wind · UV), and the single highest-priority anomaly badge (priority: temp if |delta| ≥ 1 °C, else mugginess if shown, else rain if not "Near normal", else none).
2. **HourlyPage**: next 12 h — compact Swift Charts line (temp) with precip bars beneath, or a `List` of hour rows (symbol, temp, rain %) — implementer's choice, list is easier.
3. **DailyPage**: 7 rows: weekday, condition symbol, lo–hi with a range bar tinted vs. the historical band when normals are available.

### 9.1 Watch location & boot

Use the watch's own CoreLocation when authorized (it falls back to the paired phone's fix automatically). Boot order: cached last location → fresh fix → phone-synced location → "Open the iPhone app to set a location" empty state.

### 9.2 WatchConnectivity

Phone side (`PhoneSessionManager`): after every successful climatology/hourly-normals build, and on prefs/location change, send `updateApplicationContext` with `WatchSyncPayload` (Codable → JSON `Data`): `{lat, lon, name, imperial, dailyAvg: [14 × {tMax,tMin,wbMax,wbMin}], monthlyNormals: [12 × {tMax,tMin,rain}], wbAvgByHour: [24], generatedAt}`. This is a few KB. Watch side: persist the latest payload to the App Group cache; use it for anomaly computation (§6.8) only when its `lat/lon` is within ~25 km of the watch's active location — otherwise show forecast without context (never mix locations' normals).

---

## 10. Complications (watchOS widget extension)

### 10.1 Widgets and families

Three widgets in one `WidgetBundle`:

| Kind id | Families | Content |
|---|---|---|
| `CurrentConditions` | circular, corner, inline, rectangular | Circular: condition symbol above temp. Corner: temp as label, curved gauge = position of `tNow` within today's lo–hi. Inline: `{symbol} 21° H24 L15`. Rectangular: line 1 location, line 2 symbol + temp + condition, line 3 `H24 L15` + short anomaly text when available. |
| `TempAnomaly` | circular, inline, rectangular | The differentiator. Circular: signed delta big ("+3°") with "vs norm" caption; near-normal shows "≈". Inline: `21° · 3° warmer than normal` (or `· near normal`). Rectangular: temp + full badge text + hi/lo. Requires normals from cache; if absent, fall back to CurrentConditions content. |
| `RainChance` | circular, corner, inline | `Gauge` 0–100 % (accessoryCircular gauge style) with drop symbol; inline `Rain 40%`. |

All views live in `WeatherCore` (or a shared folder compiled into both widget targets) so Phase 8 reuses them on iOS lock screen. Every widget sets `.widgetURL` (`weatherscope://today`) and supports `.containerBackground(for: .widget)`. Provide `previewContext` placeholders with plausible static data.

### 10.2 Timeline provider

One shared `WeatherTimelineProvider`:
- Read cached forecast + normals + last location from the App Group.
- If forecast cache older than **45 min**, attempt a direct fetch (10 s timeout); on failure use stale cache (mark nothing — complications should degrade silently).
- Entries: one per hour for the next **6 hours** (temp/condition from hourly arrays; hi/lo and rain chance constant for the day; recompute the anomaly per entry using `avgByHour`), reload policy `.after(now + 30 min)`.
- If there is no cached location at all: placeholder "Open app" entry, `.after(now + 60 min)`.

### 10.3 Refresh discipline

watchOS budgets roughly 40–70 timeline refreshes/day for faces in rotation. The `.after(30 min)` policy plus app-driven `WidgetCenter.shared.reloadAllTimelines()` (called after every successful foreground/background fetch) is within budget. Do not schedule per-15-min reloads; do not fetch normals (archive API) from the provider — forecast only.

---

## 11. Testing

### 11.1 Fixtures

Record once via curl into `Tests/WeatherCoreTests/Fixtures/` for a fixed location (London `51.5074,-0.1278`): `forecast.json` (§4.1 URL), `climatology.json` (§4.2a), `hourly-normals-y1.json` … `y5.json` (§4.2b), `ytd.json` (§4.2c — truncate to 2000–2003 + current year if the file is huge; tests only need the math), `geocoding.json` (`name=Paris`). Tests inject a fixed `now` (pick the date the fixtures were recorded) and the location's `TimeZone`.

### 11.2 Required unit tests

- Decoding: every fixture decodes; null elements preserved.
- §6.1 wrap-around: `mmddDist("12-30","01-02") == 3`; `("01-15","01-18") == 3`; `("06-01","12-01") == 182` or less-than-wrap check.
- §6.2: today-index found by string match with a synthetic response where `past_days` alignment is off by one; nowIdx at 23:xx and at 00:xx; a UTC+13 location while "device" is UTC-8 (the deviation §1.4.2 — build expected values by hand).
- §6.8: one test per branch (3 temp branches, 5 rain branches, 4 mugginess branches incl. the `wbNorm < 8` suppression).
- §6.7: hand-computed 3-year toy dataset → exact cumulative arrays, `latestDate` lag handling, extension length capped at year end.
- §6.3: two-level monthly averaging on a toy dataset (verify it differs from naive pooling).
- Throttler: mock `URLProtocol` asserting max concurrency 3 and the 0.8/1.6/3.2/6.4 s retry ladder (use short scaled delays injected for tests).
- Cache: TTL expiry with injected clock; key rounding (51.5074 and 51.5099 share a key at 2 dp... verify chosen rounding).
- Timeline provider: given cached fixture data, produces 6 hourly entries with correct temps.

### 11.3 Manual QA checklist (run at Phase 7)

- Fresh install → allow location → full Today screen within seconds; charts fill in progressively.
- Fresh install → deny location → search-first → search works.
- Search Singapore; toggle back to My Location; relaunch → restores last source.
- Unit toggle flips every number including chart axes and scrub annotations.
- Airplane mode with warm cache → app shows cached data + stale banner rather than error.
- Watch: with phone app installed and opened once → anomaly badge appears on watch within a minute.
- Complication on an active face updates within ~1 h of a weather change (simulator: use Debug → Location changes and time travel).

---

## 12. Build & run commands

```bash
# iOS app
xcodebuild -project ios/WeatherScope.xcodeproj -scheme WeatherApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# watch app
xcodebuild -project ios/WeatherScope.xcodeproj -scheme WeatherWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build

# core tests
xcodebuild -project ios/WeatherScope.xcodeproj -scheme WeatherCore \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

(Adjust simulator names to whatever `xcrun simctl list devices available` shows.)

---

## 13. Legal / App Store notes

- **Open-Meteo attribution is required** (data is CC BY 4.0): keep the footer credit in the iOS app and add it to watch Settings/About. If the app is ever sold or ad-supported, Open-Meteo's free tier is non-commercial — a paid API plan (still keyless-ish, different host) would be needed; flag this to the user before any commercial release, don't decide it in code.
- Privacy nutrition label: Location (app functionality only, not linked to identity, no tracking). Coordinates are sent to Open-Meteo; nothing else leaves the device.
- CLGeocoder replaces Nominatim precisely so we don't need to honor OSM's usage policy from a shipped app; keep the Nominatim fallback rate-limited to 1 req/s if it's kept at all.

---

## 14. Known pitfalls (read before Phase 1, again before Phase 6)

1. **`past_days=7` offset**: today is *usually* index 7 in daily arrays and the hourly array starts 24 h back — but always locate indices by matching date/hour strings (§6.2). Off-by-one here poisons every downstream number.
2. **Timezones**: API time strings are location-local with no suffix. Compare strings to strings built from the location's `TimeZone` (`utc_offset_seconds`/`timezone` fields). Never `Date()`-format with the device timezone for indexing.
3. **Nulls everywhere**: every API value array must decode element-optional. The archive's most recent 2–5 days are often null/missing — that's the YTD `latestDate` lag, not a bug.
4. **429s**: only the archive API rate-limits in practice; the throttler (§4.4) is not optional. Do not parallelize beyond 3, do not retry more than 4 times.
5. **Delta conversion**: temperature *differences* convert °C→°F by ×9/5 only (no +32). The web app does this correctly in `_tempAnomaly`; copy it.
6. **App Groups don't cross devices**: phone↔watch is WatchConnectivity only; App Group is app↔its-own-widgets on the same device.
7. **Widget budget**: don't reload timelines more than ~2×/hour; never call archive endpoints from a provider.
8. **Location jitter**: 2-decimal rounding for cache keys, and the §9.2 25 km guard before applying synced normals.
9. **Stale async results**: after a location switch, in-flight archive tasks for the old location must not overwrite state — tag every async result with its location key and drop mismatches (the web does this with `_lazyLat/_lazyLon` checks).
10. **watchOS widget extension** must embed in the watch app, not the iOS app; check "Embed in Watch App" target membership if the gallery shows nothing.
