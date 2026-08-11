# Follow-up Plan — post-port improvements

Instructions for an implementing agent. The iOS/watchOS port described in
`IOS_APP_PLAN.md` is **complete and verified** (see `ios/README.md`). This
document specifies the remaining improvements. Work through tasks **in order**;
each ends with explicit acceptance criteria. Do not invent behavior beyond what
is written here.

**Status as of 2026-08-07: Tasks A–I done** (C and G were completed
interactively before this document's tasks were run; A, B, D, E, F, H, I were
each done and verified per their own acceptance criteria, commit-by-commit —
see `git log`). Only **J (localization) remains, deliberately deferred** per
its own instructions until the user asks for it. This document is kept as the
record of what was asked and how it was verified, not as an open TODO list.

---

## 0. Ground rules — read fully before Task A

### 0.1 The Xcode project is GENERATED. Never hand-edit `project.pbxproj`.

`ios/WeatherScope.xcodeproj/project.pbxproj` is written by
`ios/tools/generate_project.py`. Adding/removing Swift files needs **nothing**
(synchronized groups pick them up). Changing targets, bundle IDs, or build
settings means editing the Python script and re-running:

```bash
python3 ios/tools/generate_project.py
```

### 0.2 Build & test commands (run after EVERY task)

```bash
# iOS app (also builds watch app + both widget extensions as dependencies)
xcodebuild -project ios/WeatherScope.xcodeproj -scheme WeatherApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# watch app
xcodebuild -project ios/WeatherScope.xcodeproj -scheme WeatherWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build

# unit tests (run on the Mac host, no simulator needed)
cd ios/WeatherCore && swift test
```

All three must pass before a task is "done". Current baseline: **108 tests,
0 failures, 3 skipped** (the skipped ones are live-network tests; enable with
`WEATHERCORE_LIVE_TESTS=1`).

### 0.3 Things that LOOK like bugs but are correct — do not "fix" them

1. `MMDD.distance("12-30", "01-02") == 2` (not 3). Matches the web app's
   `_mmddDist` exactly; verified against node. See `ios/README.md` deviations.
2. `UnitFormatter.fixed` goes through `Decimal` instead of `String(format:)`.
   Required to match JavaScript `toFixed` on exact binary halves. Do not
   simplify.
3. Temperature **deltas** convert °C→°F by ×9/5 with **no +32**. A delta is a
   difference.
4. The current-year YTD line ends before today. That is the archive's 2–5 day
   publication lag, shown honestly — not missing data.
5. Ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) in the generator. Required so
   the App Group entitlement applies on the simulator. Only change via the
   `WEATHERSCOPE_TEAM_ID` env var (§0.6).

### 0.4 Simulator facts (hard-won — trust these)

- **Simulator-control tap/swipe coordinates are POINTS, not pixels.**
  Screenshots are 2x. The 42mm watch is 187×223 pt; the 46mm is 208×248 pt;
  the iPhone 17 is 402×874 pt. Halve screenshot pixel positions before tapping.
- **The watch complication renderer wedges.** Symptom: complications render
  blank; `log show` on the watch sim shows `"Unknown extension process"` /
  `extensionNotFound` — for *Apple's own* complications too. Fix: reboot the
  watch simulator (`xcrun simctl shutdown <name>` then `boot`). Diagnose
  against Apple's Weather complication before suspecting app code.
- **Watch-face gallery downloads never complete** in the simulator (no store
  access). Use pre-installed faces. **Exactograph** has the accessoryCorner
  slots and is already configured with our complications on the **42mm** watch.
- Two watch simulators exist. The user drives the **42mm**; check
  `xcrun simctl list devices booted` before assuming which is active.
- App Group container path (for inspecting cache/prefs):
  `xcrun simctl get_app_container <device> com.edconway.weatherscope groups`

### 0.5 Verification discipline

Never claim something works without evidence: a passing test, a build log, or
a screenshot. If the simulator blocks verification (see 0.4), say so explicitly
in your report rather than asserting success.

### 0.6 Device builds

`WEATHERSCOPE_TEAM_ID=Y4HVDTYXNL python3 ios/tools/generate_project.py`
switches all targets to automatic signing with the user's team. Running the
generator **without** the env var restores simulator ad-hoc signing. Never
commit the project in team-signed state unless asked.

---

## Task A — Put everything under version control  ⚠️ DO THIS FIRST

Nothing in `ios/` or the plan documents is committed. This is the largest
operational risk in the project.

1. `git status` — expect untracked: `IOS_APP_PLAN.md`, `FOLLOWUP_PLAN.md`,
   `ios/`. If anything ELSE appears, stop and investigate before adding.
2. Append to the existing `.gitignore` (do not overwrite it):

   ```
   # iOS build artefacts
   ios/WeatherCore/.build/
   xcuserdata/
   *.xcuserstate
   ```

3. Confirm the ignore works: `git status --short | grep -c ".build"` must be 0.
4. You are on `main`, so branch first: `git checkout -b ios-port`.
5. `git add IOS_APP_PLAN.md FOLLOWUP_PLAN.md .gitignore ios/`
6. Review what's staged: `git status`. There must be **no** `.build/`,
   `xcuserdata`, or `DerivedData` paths, and no secrets (there are none in this
   project — anything that looks like one is wrong).
7. Commit with a message like `Add native iOS + watchOS port (WeatherScope)`,
   ending with:

   ```
   Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
   ```

8. Do **not** push or open a PR unless the user asks.

**Done when:** `git log` shows the commit on `ios-port`; `git status` is clean;
`swift test` still passes (proves `.build` exclusion didn't eat source).

---

## Task B — Verify (and if needed fix) watch chart scrubbing

Status: the Hourly and Daily watch pages are Swift Charts with
`chartXSelection` + a sticky-selection modifier
(`ios/WeatherWatch/Views/StickySelection.swift`). Tapping should pin an
annotation card. Earlier scripted taps produced nothing — but those taps were
made **before** the point-vs-pixel coordinate bug (§0.4) was discovered, at
near-edge positions. It may already work.

1. Build and install on the **42mm** watch:

   ```bash
   xcodebuild -project ios/WeatherScope.xcodeproj -scheme WeatherWatch \
     -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (42mm)' \
     -derivedDataPath /tmp/wsdd build
   xcrun simctl install "Apple Watch Series 11 (42mm)" \
     "/tmp/wsdd/Build/Products/Debug-watchsimulator/WeatherScope Watch App.app"
   xcrun simctl launch "Apple Watch Series 11 (42mm)" com.edconway.weatherscope.watchkitapp
   ```

2. Swipe vertically (the pages are a vertical `TabView`) to the Hourly page,
   then tap **the centre of the plot**, e.g. (93, 120) in point space. Screenshot.
3. Repeat on the Daily page: tap a bar centre, e.g. (93, 110). Screenshot.
4. **Pass:** a small dark annotation card appears (hour + rain % on Hourly;
   day + low/high on Daily) and persists after finger-up.
5. **Fail:** apply this fallback to BOTH charts — replace reliance on
   `chartXSelection` with an explicit tap gesture. In
   `ios/WeatherWatch/Views/HourlyPage.swift`, add to the temperature `Chart`
   (and analogously in `DailyPage.swift`):

   ```swift
   .chartOverlay { proxy in
       GeometryReader { geo in
           Rectangle().fill(.clear).contentShape(Rectangle())
               .onTapGesture { location in
                   let origin = geo[proxy.plotFrame!].origin
                   let x = location.x - origin.x
                   if let date: Date = proxy.value(atX: x) {
                       selectedDate = date
                   }
               }
       }
   }
   ```

   For `DailyPage` the value type is `String`:
   `if let day: String = proxy.value(atX: x) { selectedDate = day }`.
   Keep the existing `stickyXSelection` modifier (it also handles reset-on-
   location-change). Re-run step 2–4 to confirm.

**Done when:** screenshots show the annotation card on both pages, and both
builds + tests pass.

---

## Task C — Rename the app  🛑 GATED: ask the user first

Do not start until the user states the final name. Candidates researched:
"Weathered" (risky — existing App Store app "Weather'd"), "Weather World"
(clear, generic). Never guess.

Given `NAME` (e.g. `Weather World`) and a lowercase slug `SLUG` (e.g.
`weatherworld`):

1. `ios/tools/generate_project.py`: update `BUNDLE_APP`, `BUNDLE_WATCH`,
   `BUNDLE_WATCH_WIDGETS`, `BUNDLE_IOS_WIDGETS`
   (`com.edconway.<SLUG>` + suffixes) and the two `PRODUCT_NAME` values
   (`"NAME"`, `"NAME Watch App"` — keep the quoting style used there).
2. `ios/WeatherCore/Sources/WeatherCore/AppConfig.swift`: `appGroup`
   (`group.com.edconway.<SLUG>`), `backgroundRefreshTaskID`
   (`com.edconway.<SLUG>.refresh`), `deepLinkScheme` (`<SLUG>`),
   `todayDeepLink` (`<SLUG>://today`).
3. `ios/Support/*.plist` (4 files): `BGTaskSchedulerPermittedIdentifiers`,
   `CFBundleURLSchemes`, `CFBundleURLName`, `WKCompanionAppBundleIdentifier`.
4. `ios/Support/*.entitlements` (4 files): the App Group string.
5. Logger subsystems `"com.edconway.weatherscope"` in
   `ios/WeatherApp/Sync/PhoneSessionManager.swift`,
   `ios/WeatherApp/Store/BackgroundRefresh.swift`,
   `ios/WeatherWatch/Sync/WatchSessionManager.swift`,
   `ios/WeatherWatch/Store/WatchBackgroundRefresh.swift`.
6. Display strings: `SettingsSheet.swift` (`LabeledContent("App", ...)`),
   `WeatherEntrySnapshot` widget display names in
   `ios/WeatherWidgets/Widgets/*.swift` and
   `ios/WeatherWatchWidgets/Widgets/WatchWidgets.swift`
   (`configurationDisplayName`).
7. Sweep for stragglers — this is the authoritative check, not the list above:

   ```bash
   grep -rn "weatherscope\|WeatherScope" ios/ --include="*.swift" \
     --include="*.plist" --include="*.entitlements" --include="*.py" | grep -v README
   ```

   Handle every hit. (`ios/README.md` may keep historical mentions; update its
   current-state sections.) Renaming the *directories/targets* themselves
   (WeatherApp → etc.) is NOT required — internal target names are invisible
   to users; leave them.
8. Regenerate the project, rebuild everything. **Uninstall the old-bundle-ID
   apps** from both simulators (`xcrun simctl uninstall ...`) — the new bundle
   ID is a different app; the old one lingers otherwise. Reinstall, relaunch,
   screenshot the app showing weather.

**Done when:** grep in step 7 returns only README/doc mentions; both builds and
tests pass; fresh install runs on iPhone and watch sims.

---

## Task D — Local units toggle on the watch

Plan §Phase 5 called for a watch-local imperial/metric toggle; currently units
only sync from the phone. `WatchStore.imperial` already persists via its
`didSet` — only UI is missing.

In `ios/WeatherWatch/Views/NowPage.swift`, add below `badgeOrFallback` inside
the `VStack`:

```swift
Button {
    store.imperial.toggle()
} label: {
    Text(store.imperial ? "Switch to °C" : "Switch to °F")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
}
.buttonStyle(.plain)
.padding(.top, 6)
.accessibilityHint("Changes temperature and wind units")
```

Note `NowPage` takes `let store: WatchStore` — that is fine: `WatchStore` is
`@Observable`, and mutating `store.imperial` through a `let` reference works.

**Done when:** watch build passes; on the sim, tapping the button flips every
number on all three pages (16°C→61°F etc.) and survives app relaunch
(persistence via `Prefs`). Screenshot before/after. One caveat to preserve:
the next phone sync overwrites the choice (`applySyncedPayload` sets
`imperial = payload.imperial`) — that matches the plan ("units synced from
phone prefs, plus local toggle") and is acceptable; do not redesign it.

---

## Task E — Deep-link handling (widget tap → matching panel)

The scheme is registered and every widget sets `.widgetURL`, but the iOS app
has no `onOpenURL` handler, so taps just open the app. Wire the URL through to
the existing badge-jump scroll mechanism.

1. In `ios/WeatherCore/Sources/WeatherCore/AppConfig.swift` add:

   ```swift
   /// Deep link that scrolls the Today screen to a specific panel.
   public static func panelDeepLink(_ panel: PanelID) -> URL {
       URL(string: "\(deepLinkScheme)://panel/\(panel.rawValue)")!
   }

   /// Inverse of `panelDeepLink`. Returns nil for the plain today link.
   public static func panel(from url: URL) -> PanelID? {
       guard url.scheme == deepLinkScheme, url.host == "panel" else { return nil }
       return PanelID(rawValue: url.lastPathComponent)
   }
   ```

2. `ios/WeatherApp/Store/WeatherStore.swift`: add a published field
   `var pendingPanelJump: PanelID?` (plain `var`, it's `@Observable`).
3. `ios/WeatherApp/WeatherScopeApp.swift`: on the `TodayScreen(...)` view add

   ```swift
   .onOpenURL { url in
       store.pendingPanelJump = AppConfig.panel(from: url)
   }
   ```

4. `ios/WeatherApp/Screens/TodayScreen.swift`: inside `loadedScroll`'s
   `ScrollViewReader` closure, on the `ScrollView` add:

   ```swift
   .onChange(of: store.pendingPanelJump) { _, panel in
       guard let panel else { return }
       withAnimation { proxy.scrollTo(panel, anchor: .top) }
       store.pendingPanelJump = nil
   }
   ```

   (The panels already carry `.id(PanelID...)` via `PanelCard`.)
5. Point the iOS widgets at their panels in
   `ios/WeatherWidgets/Widgets/LockScreenWidgets.swift` and
   `HomeScreenWidgets.swift`:
   - Rain widget: `.widgetURL(AppConfig.panelDeepLink(.rain))`
   - Anomaly widget: `.widgetURL(AppConfig.panelDeepLink(.temperature))`
   - Conditions + Hero widgets: keep `AppConfig.todayDeepLink`.
   Leave the **watch** widgets on `todayDeepLink` — the watch app has no
   panel scroll; its deep link just opens the app. Do not add tab-selection
   plumbing for this.
6. Add a `WeatherCore` unit test (new file
   `Tests/WeatherCoreTests/DeepLinkTests.swift`): round-trip every `PanelID`
   through `panelDeepLink`/`panel(from:)`, and assert `panel(from:)` is nil
   for `weatherscope://today` and for a foreign scheme.
7. Verify live: install the iOS app, add the Rain lock-screen or home widget
   (see §0.4 for gallery interaction), tap it, screenshot showing the Today
   screen scrolled to the Rain panel. If widget-gallery automation proves
   flaky, verifying via `xcrun simctl openurl booted "weatherscope://panel/panel-rain"`
   with the app installed is acceptable evidence.

**Done when:** tests pass including the new file; `simctl openurl` (or a real
widget tap) visibly scrolls to the right panel.

---

## Task F — Make the corner complication respect face tinting

On heavily tinted faces the arc text renders but the inline condition symbol
can disappear into the tint. Mark the hierarchy accentable so the face's
accent colour picks out the right elements.

In `ios/WeatherCore/Sources/WeatherCore/WidgetViews/WidgetContentViews.swift`,
in `CurrentConditionsContent.corner` (watchOS branch), change:

```swift
return glyph
    .widgetLabel { cornerCurvedLabel }
```

to:

```swift
return glyph
    .widgetAccentable()
    .widgetLabel { cornerCurvedLabel.widgetAccentable() }
```

Apply `.widgetAccentable()` similarly to the circular/rectangular layouts' main
`Image`/temperature `Text` in all three content views (`CurrentConditions`,
`TempAnomaly`, `RainChance`) — top-level, one modifier per layout, no other
changes. `widgetAccentable` is available on both platforms wherever WidgetKit
is (the file already `#if canImport(WidgetKit)`-guards; put the modifier
usage inside views but note the corner is already `#if os(watchOS)`-gated —
non-watch fallback branch needs no change).

**Done when:** all builds pass; on the Exactograph face the corner still shows
`17° / SUNSET hh:mm` (screenshot; remember the renderer-wedge workaround §0.4).
A tint-mode visual diff is nice-to-have, not required.

---

## Task G — Final app icon  🛑 GATED: ask the user first

Four rendered candidates were reviewed; the user has NOT picked one. Ask:
A (trend line + sun/cloud), B (actual-vs-normal dual line), C (split dial),
D (minimal sparkline — was recommended). Never pick silently.

Generators live in the repo: `ios/tools/icon_gen.swift` (current placeholder)
and `ios/tools/icon_candidates.swift` (renders all four to a directory):

```bash
swift ios/tools/icon_candidates.swift /tmp/icons   # writes icon-<X>-*.png
```

1. Render the chosen candidate. Requirements Apple validates at upload:
   exactly **1024×1024**, **no alpha channel** (the scripts' `flatten` step
   guarantees this — verify: PNG colour type must be 2, not 6).
2. Copy it over `icon-1024.png` in all four appiconsets:
   `ios/WeatherApp/Assets.xcassets/AppIcon.appiconset/`,
   `ios/WeatherWatch/...`, `ios/WeatherWatchWidgets/...`,
   `ios/WeatherWidgets/...` (the `Contents.json` files already reference
   `icon-1024.png` — filenames must not change).
3. iOS dark/tinted variants (iOS-platform sets only — `WeatherApp`,
   `WeatherWidgets`; watchOS does not support them): render a dark variant
   (call `background(dark: true)` in the candidate function — the parameter
   already exists) as `icon-1024-dark.png`, and a greyscale copy as
   `icon-1024-tinted.png`. Replace those two sets' `Contents.json` with:

   ```json
   {
     "images" : [
       { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024",
         "filename" : "icon-1024.png" },
       { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
         "idiom" : "universal", "platform" : "ios", "size" : "1024x1024",
         "filename" : "icon-1024-dark.png" },
       { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
         "idiom" : "universal", "platform" : "ios", "size" : "1024x1024",
         "filename" : "icon-1024-tinted.png" }
     ],
     "info" : { "author" : "xcode", "version" : 1 }
   }
   ```

4. Rebuild, reinstall on the iPhone sim, screenshot the home screen icon.

**Done when:** builds pass; home-screen screenshot shows the new icon; PNG
checks (1024², colour type 2) pass for every file added.

---

## Task H — Climatology cache vs. the year boundary

`climatology` is cached 30 days keyed only by location. An entry cached in
late December stays "fresh" into January while its year range
(`yearStart`/`yearEnd`) and the derived normals go stale. Same logic applies
to `hourlyNormals` (7-day TTL) around New Year.

In `ios/WeatherCore/Sources/WeatherCore/Cache/WeatherRepository.swift`:

1. In `climatology(for:now:timeZone:)`, replace the cache-hit early return so
   a cached blob is only honoured when its window still ends last year:

   ```swift
   let thisYear = DateKit(timeZone: timeZone).year(now)
   if let cached = await cache.readFresh(
       Climatology.self, kind: .climatology, location: location),
      cached.yearEnd == thisYear - 1 {
       return cached
   }
   ```

   (Move the existing `thisYear` computation up; do not compute it twice.)
2. Same pattern in `hourlyNormals(...)`: honour the cache only when
   `cached.temp.yearEnd == DateKit(timeZone: timeZone).year(now) - 1`.
3. Add a test in `Tests/WeatherCoreTests/CacheAndPrefsTests.swift`: write a
   `Climatology` with `yearEnd: 2025` to a cache, and assert via a small
   repository-level test (or directly encode the guard as a pure function if
   the repository is awkward to instantiate — a
   `WeatherRepository(cache: DiskCache(directory: tmp, ...))` with a stub
   `URLProtocol` session for the archive client is the thorough route; if that
   exceeds one hour of effort, test the year-guard predicate extracted into a
   small internal function instead, and say so in your report).

**Done when:** tests pass including the new one; both builds pass.

---

## Task I — Widget view smoke tests (optional, do after A–H)

No third-party snapshot library (project rule: zero dependencies). Use
`ImageRenderer` on the macOS test host for existence-level regression:

New file `ios/WeatherCore/Tests/WeatherCoreTests/WidgetViewSmokeTests.swift`:

```swift
import SwiftUI
import XCTest
@testable import WeatherCore

@MainActor
final class WidgetViewSmokeTests: XCTestCase {
    private func assertRenders(_ view: some View, _ name: String) {
        let renderer = ImageRenderer(content: view.frame(width: 180, height: 180))
        XCTAssertNotNil(renderer.cgImage, "\(name) failed to render")
    }

    func testAllLayoutsRenderWithPlaceholder() {
        let entry = WeatherEntrySnapshot.placeholder
        assertRenders(CurrentConditionsContent(entry: entry, layout: .circular), "conditions.circular")
        assertRenders(CurrentConditionsContent(entry: entry, layout: .inline), "conditions.inline")
        assertRenders(CurrentConditionsContent(entry: entry, layout: .rectangular), "conditions.rectangular")
        assertRenders(CurrentConditionsContent(entry: entry, layout: .corner), "conditions.corner")
        assertRenders(TempAnomalyContent(entry: entry, layout: .circular), "anomaly.circular")
        assertRenders(TempAnomalyContent(entry: entry, layout: .rectangular), "anomaly.rectangular")
        assertRenders(RainChanceContent(entry: entry, layout: .circular), "rain.circular")
    }

    func testAllLayoutsRenderWithEmptyEntry() {
        let entry = WeatherEntrySnapshot.empty()
        assertRenders(CurrentConditionsContent(entry: entry, layout: .rectangular), "empty.rectangular")
        assertRenders(TempAnomalyContent(entry: entry, layout: .circular), "empty.anomaly")
        assertRenders(RainChanceContent(entry: entry, layout: .circular), "empty.rain")
    }
}
```

If `ImageRenderer`/`Gauge` misbehaves on macOS for some layout, drop that one
case with a comment rather than fighting it — this is a smoke net, not pixel
truth. The `corner` case on macOS exercises the non-`widgetLabel` fallback
branch by design.

**Done when:** `swift test` passes with the new cases included.

---

## Task J — Localization (DEFERRED)

Do **not** start unless the user asks. All strings are hardcoded English; the
project already sets `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`. When asked:
add a `Localizable.xcstrings` per app target, migrate user-facing literals,
and keep API/log/cache-key strings untranslated. This is pre-public-release
work, irrelevant to TestFlight.

---

## Reporting

After each task, report: what changed (files), evidence (test count, build
result, screenshot names), and anything you could not verify with the reason.
If a task's acceptance criteria cannot be met, stop that task, leave the code
building and tests green, finish the remaining unblocked tasks, and list the
blocker explicitly. Never mark a gated task (C, G) done without the user's
stated choice recorded in your report.
