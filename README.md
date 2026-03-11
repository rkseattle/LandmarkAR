# LandmarkAR

An augmented reality iOS app that overlays floating labels on nearby natural and historic landmarks using your iPhone's camera, GPS, and compass.

---

## Features

### AR View
- Live camera feed with floating landmark labels showing name, distance, and category icon
- Labels are anchored to real compass directions using ARKit's `gravityAndHeading` alignment
- Label opacity fades with distance so close landmarks are most prominent
- Tap any label to open the landmark detail sheet
- **Compass bar** at the top of the AR view shows current heading (N/NE/E/SE/S/SW/W/NW), the live heading in degrees, and chevron indicators for off-screen landmarks so you always know which way to turn

### Landmark Detail Sheet
- Full Wikipedia summary with a link to read the complete article
- **Get Directions** — opens the landmark in your preferred map app (Apple Maps, Google Maps, or Waze) with turn-by-turn directions from your current location

### Data Sources
| Source | What it provides |
|--------|-----------------|
| Wikipedia | Articles for landmarks, historic sites, parks, monuments, and more |
| OpenStreetMap | Points of interest including shops, venues, and infrastructure |

Each source can be independently enabled or disabled in Settings.

### Settings
| Setting | Options | Default |
|---------|---------|---------|
| Data Sources | Wikipedia on/off, OpenStreetMap on/off | Both on |
| Display Limit | 5 / 10 / 25 | 10 |
| Label Size | Small / Medium / Large | Medium |
| Categories | Historical, Natural, Cultural, Other — each with its own distance slider (0.1 km – 100 km) | All on, 10 km |
| Real-time Updates | Off / Wi-Fi Only / Always | Off |
| Language | 8 languages (see below) | Device language |

### Language Support
The app is fully localized in 8 languages. Wikipedia content is fetched from the matching language subdomain (e.g. `ja.wikipedia.org` when Japanese is selected), so landmark descriptions are in your chosen language with no machine translation.

| Language | Native name |
|----------|-------------|
| English | English |
| Japanese | 日本語 |
| German | Deutsch |
| French | Français |
| Spanish | Español |
| Portuguese | Português |
| Korean | 한국어 |
| Italian | Italiano |

### Reliability
- **Circuit breaker** — if a data source fails repeatedly it is paused automatically and retried after a cooldown, preventing error spam
- **Network awareness** — real-time updates can be restricted to Wi-Fi to save mobile data
- **Error log** — all fetch errors are timestamped and viewable in Settings → Diagnostics → Error Log

---

## Requirements

| Requirement | Minimum |
|-------------|---------|
| Xcode | 15.0+ |
| iOS | 17.0+ |
| Device | iPhone with ARKit support (iPhone 6s or newer) |
| Apple Developer Account | Free account is sufficient for personal device testing |

> **ARKit does not work in the iOS Simulator.** Run on a real iPhone for the AR view.

---

## Building and Running

### 1. Open the project
Double-click **LandmarkAR.xcodeproj** to open it in Xcode.

### 2. Sign the app
1. Select the **LandmarkAR** target in the Project navigator
2. Open the **Signing & Capabilities** tab
3. Under **Team**, select your Apple ID (add it via Xcode → Settings → Accounts if needed)
4. Set a unique **Bundle Identifier** — e.g. `com.yourname.LandmarkAR`

### 3. Connect your iPhone and run
1. Plug in your iPhone and select it from the device picker at the top of Xcode
2. Press **⌘R** to build and run
3. If iOS shows "Untrusted Developer": Settings → General → VPN & Device Management → your Apple ID → Trust
4. Grant location and camera permissions when the app prompts you

---

## Project Structure

```
LandmarkAR/
├── LandmarkARApp.swift              # App entry point + splash screen transition
├── Models/
│   ├── Landmark.swift               # Landmark model + Wikipedia API response types
│   ├── AppSettings.swift            # User preferences (UserDefaults-backed)
│   ├── AppLanguage.swift            # Supported languages enum
│   ├── LocaleBundleEnvironment.swift# SwiftUI environment key for runtime localization
│   ├── DataSourceCircuitBreaker.swift # Per-source failure tracking + cooldown
│   └── ErrorLog.swift               # In-memory + persisted error log
├── Services/
│   ├── LocationManager.swift        # GPS + compass (CoreLocation)
│   ├── WikipediaService.swift       # GeoSearch + Summary API calls
│   ├── OpenStreetMapService.swift   # Overpass API calls
│   ├── ElevationService.swift       # Open-Meteo elevation lookup
│   ├── NetworkMonitor.swift         # Wi-Fi / cellular detection (Network framework)
│   └── NPSService.swift             # National Park Service (disabled; kept for future use)
├── AR/
│   └── ARLandmarkView.swift         # ARSCNView + label placement + tap handling
├── Views/
│   ├── ContentView.swift            # Root view + fetch orchestration
│   ├── CompassBarView.swift         # Compass heading bar + off-screen landmark chevrons
│   ├── SettingsView.swift           # Settings form
│   ├── LandmarkDetailSheet.swift    # Summary sheet + directions + Wikipedia link
│   ├── ErrorLogView.swift           # Timestamped error list
│   └── SplashScreenView.swift       # Launch screen
└── Resources/
    ├── Info.plist
    ├── Assets.xcassets
    └── [en/ja/de/fr/es/pt/ko/it].lproj/Localizable.strings
```

---

## Testing

### Unit Tests

Run with **⌘U** in Xcode or `xcodebuild test -scheme LandmarkAR`. All unit tests are fast and offline.

### Integration Tests

Integration tests make live network calls to Wikipedia, OpenStreetMap, Open-Elevation, and Wikidata. They are skipped by default and must be opted in.

**To run in Xcode:**
1. Product → Scheme → Edit Scheme → Test → Arguments → Environment Variables
2. Add `RUN_INTEGRATION_TESTS` = `1`
3. Press **⌘U**

**To run from the command line:**
```
RUN_INTEGRATION_TESTS=1 xcodebuild test -scheme LandmarkAR
```

| Integration test class | API under test |
|------------------------|---------------|
| `WikipediaServiceIntegrationTests` | Wikipedia GeoSearch + Summary + Pageviews |
| `OpenStreetMapServiceIntegrationTests` | Overpass API |
| `ElevationServiceIntegrationTests` | Open-Elevation API |
| `WikidataServiceIntegrationTests` | Wikidata sitelinks API + Wikipedia GeoSearch |

---

## How It Works

1. **Location** — `LocationManager` streams GPS fixes and compass headings via CoreLocation
2. **Fetch** — `ContentView` calls each enabled data source when the app opens, after moving 200 m, or on a 30-second timer (when real-time mode is on). Results from all sources are merged and deduplicated by title and geographic proximity (within 75 m)
3. **Elevation** — `ElevationService` fetches altitudes from Open-Meteo in a single batch request; labels are vertically offset by the landmark's elevation relative to the user
4. **Bearing math** — For each landmark, a haversine bearing from the user's coordinate is calculated so the label can be placed in the correct compass direction
5. **AR placement** — ARKit's `gravityAndHeading` world alignment anchors the AR coordinate system to magnetic north. Labels are placed at 80 m radius in the computed bearing direction and projected onto the camera plane
6. **Language** — `AppSettings.appLanguage` controls both the UI locale (via language-specific `.lproj` bundles loaded at runtime) and the Wikipedia subdomain used for all API calls

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| No labels appear | Go outside — GPS and compass require an open-sky view |
| Labels point the wrong way | Slowly wave your phone in a figure-8 to recalibrate the compass |
| Very few landmarks | Some areas have sparse Wikipedia coverage; try a city centre |
| "Untrusted Developer" on launch | Settings → General → VPN & Device Management → Trust your Apple ID |
| Data source errors | Check Settings → Diagnostics → Error Log for details |
| App won't build | Ensure you have set a unique Bundle Identifier in Signing & Capabilities |

---

## License

Copyright © 2025 Edward Aspen Studios. See [LICENSE](LICENSE) for details.
