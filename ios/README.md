# Weather World — iOS + watchOS port

Native SwiftUI port of the web app in the repo root, built to `IOS_APP_PLAN.md`.
The web app (`app.js`, `charts.js`, `search.js`) remains the reference
implementation for all weather maths.

Shipping name: **Weather World** (bundle `com.edconway.weatherworld`). Renamed
from the working name "WeatherScope" on 2026-08-06 — see `FOLLOWUP_PLAN.md`
Task C for the rename procedure if it needs repeating. Internal target/type
names (`WeatherApp`, `WeatherScopeApp.swift`, the `.xcodeproj` filename, the
`WeatherScope.app` bundle filename) were deliberately left alone; they are not
user-visible. App icon: candidate A (trend line, solid→dashed, with a
sun/cloud glyph) from the four rendered options — see `ios/tools/icon_gen.swift`
and `icon_candidates.swift`.

## Layout

```
ios/
├── WeatherScope.xcodeproj      # generated — see tools/generate_project.py
├── WeatherCore/                # local SwiftPM package: models, API, maths, widget views
├── WeatherApp/                 # iOS app
├── WeatherWatch/               # watchOS app
├── WeatherWatchWidgets/        # watchOS complications
├── WeatherWidgets/             # iOS lock-screen + home-screen widgets
└── Support/                    # Info.plists and entitlements
```

## Build & test

```bash
xcodebuild -project ios/WeatherScope.xcodeproj -scheme WeatherApp \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

```bash
xcodebuild -project ios/WeatherScope.xcodeproj -scheme WeatherWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' build
```

The `WeatherCore` tests run on the host, no simulator needed:

```bash
cd ios/WeatherCore && swift test
```

Live network tests are skipped unless opted in:

```bash
cd ios/WeatherCore && WEATHERCORE_LIVE_TESTS=1 swift test --filter LiveSmokeTests
```

## The Xcode project is generated

`ios/tools/generate_project.py` writes `project.pbxproj` and the shared schemes.
Source files live in synchronized root groups, so **adding a Swift file needs no
regeneration** — Xcode picks it up. Re-run the script only for structural changes
(new target, new build setting):

```bash
python3 ios/tools/generate_project.py
```

## Signing

Targets are set to manual ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) so the App
Group entitlement is applied on the simulator. Without it,
`containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` and the
app↔widget cache sharing silently does not exist. For device builds set
`DEVELOPMENT_TEAM` and switch `CODE_SIGN_STYLE` back to `Automatic` in
`generate_project.py`.

## Deviations from the plan

The plan's own §1.4 deviations are all implemented. Beyond those:

1. **`MMDD.distance("12-30", "01-02")` is 2, not the 3 the plan's §11.2 predicts.**
   `_mmddDist` in `app.js` measures in leap year 2020 (366 days) but wraps by
   subtracting 365. Ground rule 2 makes the web app authoritative, so the port
   reproduces it; every case is cross-checked against node in `MMDDTests`.
2. **`UnitFormatter.fixed` replaces `String(format:)` for precip and UV.**
   `printf` rounds exact binary halves to even, `toFixed` rounds away from zero
   (1.25 → "1.2" vs "1.3"). Verified identical to `toFixed` across 12 cases.
3. **Hourly charts use all 72 points.** The web app re-slices to ±24 h because
   `past_days=7` used to override `past_hours`; the API now honours
   `past_hours=24&forecast_hours=48` and returns exactly the 72 points §8.4.1
   asks for.
4. **`DailyRainDeriver` takes the string-matched today index** rather than the
   web's hardcoded `min(7, len-1)`, per §14.1.
5. **YTD `latestDate` is the last date that actually has data**, per §6.7 —
   the web app takes the last row present regardless of nulls.
6. **Chart scrub selections persist after the gesture ends.**
   `chartXSelection` resets to `nil` on finger-up, so the annotation would flash
   and vanish; the web tooltip stays put while the pointer is over the chart.
   `StickyXSelection` also clears the selection when the underlying data changes,
   so switching location cannot leave a stale card relabelled with new numbers.
7. **Daily charts use a categorical x-axis** on the date string: weekday names
   repeat across 14 days, and a `Date` axis bins bars to day boundaries, which
   pushed the "Today" rule half a slot off.
8. **Widget timeline reloads are throttled to 2/hour** (`WidgetReloadThrottle`).
   §10.3 asks for a reload after every fetch, but §14.7 caps it — and a single
   app session fires up to four data-changed events.
9. **The phone writes its own `watchPayload` to the App Group cache** in addition
   to sending it over WatchConnectivity, so the *iOS* "vs Normal" widget has
   normals. App Groups don't cross devices (§14.6), so these are two jobs.
10. **watchOS `.backgroundTask(.appRefresh)` takes `String?`**, not `Void` — the
    scheduler's `userInfo` is handed to the action.
11. **`sunrise` and `sunset` are added to the forecast request.** The web app
    does not use them; the corner complication does (see below).
12. **Complication content is `.widgetAccentable()`** on its primary
    icon/temperature/delta element (not secondary text, not `Gauge`-based
    layouts, which already tint via `.tint()`), so a tinted watch face or
    monochrome Lock Screen recolors the number that matters.
13. **Climatology and hourly-normals cache reads also check the cached year
    window**, not just the TTL. A blob built in late December is still within
    its 30-day TTL through most of January while describing the wrong decade
    — see `WeatherRepository.climatology`/`.hourlyNormals`.

## The corner complication

`accessoryCorner` on `CurrentConditionsWidget` shows three things:

```
              32°
      SUNSET 20:58 ⛅
```

| Where | What |
|---|---|
| Corner text | Temperature — the number you glance at |
| Curved bezel label | Next sun event, then the condition symbol |

`SunEvent.next(forecast:now:)` picks sunrise vs. sunset by string comparison
against now in the **location's** timezone, so a searched city on the other side
of the world shows its own dawn. Each of the six timeline entries recomputes it,
so the label flips from `SUNSET` to `SUNRISE` at dusk without waiting for a
reload.

Inside the polar circles Open-Meteo returns `null` sun times for weeks at a
time; the arc then falls back to `H8 L3` rather than inventing a time.

## Verification status

Verified on simulator: iOS today screen (GPS + custom location, both unit
systems, both themes), search, source toggle, all 8 charts for London and
Singapore, scrubbing with actual/forecast tagging, watch app with direct
forecast fetch, phone→watch sync delivering the anomaly badge, the 25 km
normals guard rejecting a mismatched location, complications listed and
rendering in the on-watch gallery, and the iOS home-screen widget showing live
cached data.

Also verified on-face: the corner complications live on Exactograph — the
Conditions corner rendering real data (`17°` in the corner, `SUNSET 20:40` on
the arc) and the RainChance corner gauge beside it. Note the simulator's
complication renderer occasionally wedges (`chronod` logs
`"Unknown extension process"` for *every* app's complications, Apple's
included); a simulator reboot clears it.

**Chart scrubbing on the watch pages**: `chartXSelection`'s built-in tap
gesture did not respond to scripted taps in the watchOS simulator (on either
the 42mm or 46mm device). Both `HourlyPage` and `DailyPage` now also carry an
explicit `.chartOverlay` tap handler as a fallback — confirmed live: tapping
the Hourly temperature chart and a Daily range bar both pin a scrub card that
persists after finger-up.

**Widget deep links**: confirmed live via `xcrun simctl openurl` with
`weatherworld://panel/panel-temperature` and `.../panel-rain`, both against a
cold-started and an already-frontmost app — the Today screen scrolls to the
right panel both times.

**Watch-local units toggle**: confirmed live — tapping the toggle on the Now
page flips every number across all three pages and survives a relaunch.

Not verified interactively:

- **Background-refresh launches.** The simulator has no `BGTaskScheduler`; use
  the lldb trick in plan §7.4.
- **`.widgetAccentable()`'s actual tinted appearance.** The modifier is applied
  per Apple's documented API and doesn't change untinted rendering (confirmed:
  the corner complication still renders correctly after the change), but
  putting a face into tinted/Always-On mode to see the recolor itself wasn't
  achieved in the simulator.
