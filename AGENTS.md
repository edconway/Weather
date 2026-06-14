# Weather

A client-side weather web app (vanilla HTML/CSS/JS, no framework, no build step). Data comes from the public Open-Meteo APIs (forecast/archive/geocoding) and Nominatim/OSM reverse geocoding, all called directly from the browser with no API keys.

## Cursor Cloud specific instructions

- There is no package manager, build step, lint config, or test suite. The "app" is the set of static files (`index.html`, `app.js`, `charts.js`, `search.js`, `icons.js`, `styles.css`).
- Run it by serving the repo root over HTTP and opening it in a browser, e.g. `python3 -m http.server 8000` then visit `http://localhost:8000`. Do not just `file://` open it (fetch/CORS and relative script loads expect an HTTP origin).
- The app needs outbound internet to `open-meteo.com` and `nominatim.openstreetmap.org`. There are no secrets to configure.
- On load it asks for browser geolocation. In a headless/automated browser geolocation is denied, so it falls back to a "search for a location" screen — use the search box (e.g. type a city, pick a result) to load weather. This is expected, not a bug.
- `autopush.sh` is a personal macOS auto-commit watcher for the original author's machine; ignore it for development here.
