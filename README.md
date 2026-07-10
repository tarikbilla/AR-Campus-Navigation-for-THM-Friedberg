# AR Campus Navigation for THM Friedberg

An augmented-reality wayfinding assistant that guides students and visitors across the
**THM (Technische Hochschule Mittelhessen) campus in Friedberg**. It shows your live GPS
position and every main building on a map, and overlays a live directional arrow and
distance onto the camera view so you can *follow the arrow* straight to any building.

Built with **Flutter** (Android) and **Google ARCore**. No account, no login — just open
the app and start navigating.

> **Walking directions only.** The app is designed for pedestrians moving on foot around the
> campus; all routes, distances and ETAs are for walking (no driving/cycling modes).

> Module: Augmented Reality — Summer Semester 2026 · Team: Tarik Billa · Sai Radhika Mitta
> Supervisors: Prof. Dr.-Ing. Hartmut Weber · M.Sc. Severin Stahl

---

## Features

- 🗺️ **Map Mode** — interactive OpenStreetMap of the campus with your live position and
  tappable building markers. The **entire campus walking-lane network** is shown as faint dashed
  paths, and selecting a building draws a **lane-following walking route** (casing + gradient line,
  direction chevrons and a small **animated walking character** that travels the route) with live
  distance/ETA.
- 📸 **AR Mode** — a real ARCore session with horizontal-plane detection and a deliberately clean
  camera view (no plane grid or clutter). Three geo-aligned 3D objects guide you: **flowing 3D
  chevrons** on the road show the next few metres to walk; a **floating 3D map pin** hovers toward
  the destination building with its **name and live distance**, so you instantly see which way it
  is; and one **professional info card** (distance · steps · ETA) floats above the road ahead.
  Everything is locked to the real world as you look around 360°, and a 2D heads-up arrow tells
  you which way to turn when the building is out of view.
- 🧭 Sensor fusion — GPS (position), compass (heading) and camera (ARCore) combined to compute
  the bearing/distance and to project the route into the AR world frame.
- 🧭 Routing — an **on-device campus footpath graph** (Dijkstra) keeps walking directions on the
  real internal campus lanes even where OpenStreetMap does not map them, works fully offline, and
  falls back to the keyless OSRM foot service off-campus (straight line if neither is available).
- 🚪 **Zero friction** — no registration, no ads, no tracking; works offline for guidance
  (map tiles need connectivity).
- 🎨 Professional Material 3 UI with light/dark themes and a THM-green identity.

The two committed phases from the project proposal — **Map mode** and **AR camera mode** — are
implemented here. Indoor room-level navigation is documented as a future outlook in the PRD.

## Tech stack

| Concern | Choice |
|---|---|
| App framework | Flutter (Android target) |
| Map | `flutter_map` + OpenStreetMap tiles (no API key) |
| AR | Native **ARCore** (`com.google.ar:core`) via a Flutter hybrid-composition `PlatformView` |
| Routing | On-device campus footpath graph (Dijkstra); keyless OSRM foot service off-campus |
| Location | `geolocator` |
| Orientation | `flutter_compass` |
| Permissions | `permission_handler` |

## Project structure

```
lib/
  core/            theme, constants, geo utilities (distance & bearing)
  data/            CampusBuilding model + THM Friedberg building dataset
  services/        location, compass, permissions, ARCore availability
  features/
    home/          home screen (mode selection)
    map/           Map mode (flutter_map + markers + info sheet)
    ar/            AR mode (native view wrapper + directional HUD)
  widgets/         shared building tile / building picker
android/app/src/main/kotlin/net/godevs/thmcampusnav/
  MainActivity.kt          registers the AR platform view + ARCore availability channel
  ar/ArView.kt             ARCore session + GLSurfaceView renderer (plane detection)
  ar/rendering/            camera background, plane, and world-anchor GL renderers
```

## Requirements

- Flutter 3.44+ / Dart 3.12+
- Android SDK (min SDK 24, required by ARCore)
- A physical **ARCore-supported** device to experience AR mode (Map mode works everywhere).
  ARCore is declared *AR Optional*, so the app installs and runs on all devices.

## Getting started

```bash
flutter pub get
flutter run                       # debug on a connected Android device
```

### Regenerate launcher icons (optional)

```bash
dart run flutter_launcher_icons
```

## Release build (Google Play)

```bash
flutter build appbundle --release      # produces build/app/outputs/bundle/release/app-release.aab
```

The release build is minified and resource-shrunk. Before publishing, replace the debug
signing config in `android/app/build.gradle.kts` with your own upload key.

**Package ID:** `net.godevs.thmcampusnav`

## Permissions & privacy

| Permission | Why |
|---|---|
| Camera | AR navigation (live camera overlay) |
| Location (fine/coarse) | Show your position and compute bearing/distance to buildings |
| Internet | Load OpenStreetMap map tiles |

No personal data is collected, stored off-device, or shared. Location and camera are
processed on-device in real time. See [`docs/PRD.md`](docs/PRD.md) for the full product requirements.

## Notes on campus data

Building codes (A1–A8, B1–B2, C1, Mensa) and coordinates in
`lib/data/campus_data.dart` are sourced from the OpenStreetMap mapping of the THM Friedberg
campus (Wilhelm-Leuschner-Straße 13, 61169 Friedberg). They are centralised in one file, so
positions or descriptions can be refined (e.g. against the official campus plan) without
touching any UI or logic code.

### Campus walking-path network

The internal pedestrian lanes used for routing live in `lib/data/campus_paths.dart` as
`footways` — the **real OpenStreetMap footpath geometry** for the campus (the same dashed paths
you see on the map tiles), clipped to the campus area. The routing graph (nodes, junctions and
adjacency) is built from this geometry at runtime by de-duplicating shared coordinates, and
routing is restricted to the largest connected component so it never dead-ends on an isolated
fragment. The map draws exactly these polylines, so the shown lanes and the routed path always
sit on the real footpaths.

To refresh after OSM edits, re-run the Overpass import for the campus bounding box:

```bash
curl -H 'User-Agent: THMCampusNav/1.0' -G 'https://overpass-api.de/api/interpreter' \
  --data-urlencode 'data=[out:json][timeout:40];
  (way["highway"~"^(footway|path|pedestrian|steps|cycleway|living_street|service)$"](50.3272,8.7548,50.3322,8.7612););
  out geom;'
```

then regenerate the `footways` literal (round to 6 dp, clip to the campus box, drop tiny stubs).
Routing over this graph (Dijkstra + origin/destination snapping) is verified by
`test/campus_router_test.dart`, which also asserts every route vertex lies on a real footpath.
