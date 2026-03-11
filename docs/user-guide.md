# LandmarkAR — User Guide

This guide explains everything you can do in LandmarkAR.

---

## Getting Started

When you first launch the app:

1. **Allow Location Access** — tap *Allow While Using App*. LandmarkAR needs your GPS location to find nearby landmarks and aim the AR labels correctly.
2. **Allow Camera Access** — tap *OK*. The camera is the foundation of the AR view.
3. **Go outside** — GPS and compass accuracy are significantly better outdoors with a clear view of the sky.

Once you have a GPS fix the AR camera activates and labels begin to appear.

---

## The AR View

The camera shows your real surroundings. Floating labels are overlaid in the direction each landmark physically exists from where you are standing.

Each label shows:
- An icon indicating the landmark's category (see [Categories](#categories))
- The landmark's name
- Its distance from you

**If labels look misaligned**, slowly wave your phone in a figure-8 pattern to recalibrate the compass. This is a normal iPhone compass calibration step.

### Compass Bar

A compass bar is pinned to the top of the AR view. It shows:

| Element | Description |
|---------|-------------|
| Tick marks | A scrolling degree scale — minor ticks every 5°, major ticks every 10° |
| Cardinal labels | **N**, **E**, **S**, **W** in bold; NE, SE, SW, NW in smaller text |
| Heading readout | Your exact current heading in degrees (e.g. `157°`), updated in real time |
| Center marker | A white triangle at the top-center indicating your exact heading |
| Landmark chevrons (▲) | Small triangles that appear at the bearing of any landmark **outside your camera view**. Larger chevrons indicate more significant landmarks. Turn toward a chevron to bring that landmark into frame. |

If the compass is still calibrating, the bar shows **"Calibrating compass…"** instead. Wave your phone in a figure-8 to speed up calibration.

### Tapping a Label

Tap any label to open the **Landmark Detail Sheet** for that location.

---

## Landmark Detail Sheet

The detail sheet provides:

| Section | What it shows |
|---------|--------------|
| Distance badge | How far the landmark is from your current position |
| Summary | The Wikipedia article summary for this location |
| Get Directions | Opens your preferred map app with turn-by-turn directions |
| Read full article | Opens the complete Wikipedia page in your browser |

### Get Directions

Tap **Get Directions** to navigate to the landmark. If you have more than one map app installed (Apple Maps, Google Maps, or Waze), you will be asked which one to use.

---

## Toolbar Buttons

Two buttons appear in the top corners of the AR view:

| Button | Location | Action |
|--------|----------|--------|
| ↺ Refresh | Top left | Immediately re-fetches landmarks from all enabled data sources |
| ⚙ Settings | Top right | Opens the Settings panel |

---

## Settings

Open Settings by tapping the ⚙ button in the top right.

### Data Sources

Controls which services LandmarkAR fetches landmark data from.

| Source | What it covers |
|--------|---------------|
| **Wikipedia** | Named natural features, historic sites, monuments, museums, parks, and more |
| **OpenStreetMap** | Points of interest including shops, cafés, venues, bridges, and infrastructure |

Toggle either source off to hide its results entirely. Disabling a source also stops network requests to it.

### Display Limit

Sets the maximum number of labels shown at one time: **5**, **10**, or **25**.

When the limit is reached, LandmarkAR always keeps the *closest* and *farthest* visible landmarks and distributes the remaining slots evenly across the distance range.

### Label Size

Controls the size of the floating AR labels: **Small**, **Medium**, or **Large**.

Use Small in dense areas to reduce clutter, or Large if you find labels hard to read.

### Categories

Landmarks are automatically classified into four categories. Each category can be independently enabled or disabled, and has its own **distance slider** (0.1 km to 100 km).

| Category | Icon | Examples |
|----------|------|---------|
| Historical | 🏛 | Monuments, museums, historic buildings, battlefields, cemeteries |
| Natural | ⛰ | Mountains, lakes, rivers, parks, beaches, glaciers |
| Cultural | 🎭 | Theatres, galleries, universities, stadiums, bridges, markets |
| Other | 📍 | Everything that doesn't fit the above |

Drag the slider under a category to set its search radius. Only landmarks within that distance for that category are shown, even if they were fetched.

> **Tip:** Set Natural to 100 km to find distant mountains while keeping Historical at 2 km for walkable historic sites.

### Real-time Updates

Controls automatic landmark refresh while you use the app.

| Mode | Behaviour |
|------|-----------|
| **Off** | Landmarks refresh only when you open the app or move 200 m |
| **Wi-Fi Only** | Auto-refreshes every 30 s (or after moving 50 m) when connected to Wi-Fi; reverts to manual on cellular |
| **Always** | Auto-refreshes every 30 s or after moving 50 m, regardless of connection type |

Use *Wi-Fi Only* or *Off* to minimise mobile data usage.

### Language

Sets the display language for the app interface and the Wikipedia content language. Each option is shown in its own language.

| Language | Shown as |
|----------|----------|
| English | English |
| Japanese | 日本語 |
| German | Deutsch |
| French | Français |
| Spanish | Español |
| Portuguese | Português |
| Korean | 한국어 |
| Italian | Italiano |

Changing language immediately updates the UI and switches all Wikipedia lookups to the matching language edition (for example, selecting Deutsch fetches summaries from `de.wikipedia.org`).

If no language has been chosen the app defaults to your device's system language, or English if your system language is not in the supported list.

### Diagnostics — Error Log

Settings → Diagnostics → Error Log shows a timestamped list of any errors that occurred during landmark fetching (network failures, API errors, etc.). Tap **Clear** to empty the log.

---

## Tips and Tricks

- **Rotate slowly** — labels update in real time as you turn. Moving too fast can cause the compass to lag.
- **Elevation matters** — LandmarkAR factors in each landmark's altitude, so a mountain summit label appears higher in your view than a valley lake.
- **Dense areas** — lower the Display Limit to 5 or 10 in cities to keep the view readable.
- **Remote areas** — increase per-category distances and enable both data sources to find more landmarks.
- **Battery** — real-time updates and constant GPS usage increase battery drain. Use *Off* or *Wi-Fi Only* for longer sessions.

---

## Privacy

LandmarkAR uses your location only to find nearby landmarks. Location data is never stored or transmitted — it is used locally on your device to query the Wikipedia and OpenStreetMap public APIs. No account or sign-in is required.
