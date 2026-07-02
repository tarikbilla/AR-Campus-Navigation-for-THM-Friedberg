# AR Campus Navigation for THM Friedberg

An augmented-reality wayfinding assistant that guides students and visitors across the
**THM (Technische Hochschule Mittelhessen) campus in Friedberg**. It shows your live GPS
position and every main building on a map, and overlays a live directional arrow and
distance onto the camera view so you can *follow the arrow* straight to any building.

Built with **Flutter** (Android) and **Google ARCore**. No account, no login — just open
the app and start navigating.

> Module: Augmented Reality — Summer Semester 2026 · Team: Tarik Billa · Sai Radhika Mitta
> Supervisors: Prof. Dr.-Ing. Hartmut Weber · M.Sc. Severin Stahl

---

## Features

- 🗺️ **Map Mode** — interactive OpenStreetMap of the campus with your live position and
  tappable building markers. Selecting a building draws a **road-following walking route**
  (casing + gradient line, direction chevrons and an animated "comet") with live distance/ETA.
- 📸 **AR Mode** — a real ARCore session with horizontal-plane detection that draws the walking
  route as a **ground-hugging ribbon on the real path** with a flowing animation, plus a glowing
  **beacon** at the destination and a directional arrow HUD. The path and beacon are geo-aligned,
  so they stay locked to the world as you look around 360° — showing exactly which way to walk.
- 🧭 Sensor fusion — GPS (position), compass (heading) and camera (ARCore) combined to compute
  the bearing/distance and to project the route into the AR world frame.
- 🧭 Routing — real pedestrian routes via the keyless OSRM foot service (the routing backend
  used by openstreetmap.org), with a straight-line fallback when offline.
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
| Routing | Keyless OSRM foot service (`routing.openstreetmap.de`) via `http` |
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
processed on-device in real time. See [`PRD.md`](PRD.md) for the full product requirements.

## Notes on campus data

Building codes (A1–A8, B1–B2, C1, Mensa) and coordinates in
`lib/data/campus_data.dart` are sourced from the OpenStreetMap mapping of the THM Friedberg
campus (Wilhelm-Leuschner-Straße 13, 61169 Friedberg). They are centralised in one file, so
positions or descriptions can be refined (e.g. against the official campus plan) without
touching any UI or logic code.
