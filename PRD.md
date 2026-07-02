# Product Requirements Document (PRD)

## AR Campus Navigation for THM Friedberg

| | |
|---|---|
| **Product name** | AR Campus Navigation for THM Friedberg |
| **Platform** | Android (Google Play Store) |
| **Category** | Maps & Navigation / Education |
| **Module** | Augmented Reality — Summer Semester 2026 |
| **Supervisors** | Prof. Dr.-Ing. Hartmut Weber · M.Sc. Severin Stahl |
| **Project team** | Tarik Billa · Sai Radhika Mitta |
| **Core framework** | Google ARCore (Android), Flutter UI |
| **Core sensors** | GPS, compass / orientation sensors, camera |
| **Document status** | v1.0 — committed scope (Phases 1 & 2) |
| **Last updated** | 2026-07-02 |

---

## 1. Overview

AR Campus Navigation is an augmented-reality wayfinding assistant that guides students
and visitors across the THM (Technische Hochschule Mittelhessen) campus in Friedberg.
Using the smartphone's GPS, compass and camera, the app first shows the user's live
position relative to the campus buildings on a **map**, and then, in **AR mode**, overlays
directional indicators and route guidance directly onto the camera view of the real path
ahead.

The app requires **no account, no login and no registration** — the user opens the app and
immediately starts navigating. It is designed to be published on the Google Play Store and
to fully comply with Play Store policies.

---

## 2. Problem Statement & Motivation

Finding the right building, entrance or lecture hall on an unfamiliar campus is a common
and stressful problem — especially for first-semester students during their first days, and
for external visitors attending events or examinations.

Conventional maps and static signage require the user to mentally translate a top-down plan
into the real world, which is error-prone and slow. By anchoring guidance to the user's
actual position and turning the live camera view into an intuitive *follow-the-arrow*
experience, the application removes this translation step and makes orientation on campus
noticeably **faster, clearer and more confident**.

---

## 3. Goals & Success Metrics

### 3.1 Goals
- Let a first-time visitor reach any main THM Friedberg building without prior knowledge.
- Provide two complementary navigation modes: a familiar **Map mode** and an immersive
  **AR camera mode**.
- Zero-friction usage: open and go, no sign-up.
- Ship a production-quality, Play-Store-compliant Android app.

### 3.2 Success Metrics
| Metric | Target |
|---|---|
| Direction accuracy | App points toward the correct building from arbitrary on-campus positions |
| Distance accuracy | Displayed distance within GPS tolerance (typically ±5–15 m) |
| Task success | A person unfamiliar with the site reaches the target entrance without extra help |
| Cold start | App usable within a few seconds of launch, no onboarding wall |
| Crash-free sessions | ≥ 99% |

---

## 4. Target Users / Personas

1. **First-semester student** — does not know the campus, needs to find lecture halls and
   labs quickly during the first weeks.
2. **Applicant / prospective student** — visiting for an open day or entrance interview.
3. **External visitor** — attending an event, exam, or meeting on campus.

All personas share one need: *"Which way is building X, and how far is it?"* — answerable in
seconds, with no setup.

---

## 5. Scope

### 5.1 In scope (committed core deliverable)

**Phase 1 — Map mode**
- Display a campus map centred on THM Friedberg.
- Show the user's live GPS position.
- Show the main THM Friedberg buildings as labelled markers.
- Let the user select a building to see its name, distance and bearing.
- Provide a one-tap handoff into AR mode for the selected building.

**Phase 2 — AR camera mode**
- Open the live camera view via ARCore with plane detection.
- Overlay a directional indicator (arrow) pointing toward the selected building.
- Overlay the live distance to the building.
- Provide clear turn guidance ("turn left / right / straight / behind you").
- Re-select target building from within AR mode.

### 5.2 Out of scope (future outlook — **not** part of committed scope)
- **Indoor navigation** to locate specific floors and rooms once a building is reached.
- Turn-by-turn walking routes along footpaths (currently straight-line bearing guidance).
- iOS build, accounts, social features, cloud sync, analytics dashboards.

> Note: Phases 1 and 2 constitute the core deliverable for the available project time. The
> indoor-navigation extension is documented as an outlook only.

---

## 6. System Architecture

The application follows a simple, robust pipeline:

```
 ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
 │     GPS     │   │  Compass /  │   │   Camera    │   ← 3 device sensors (raw input)
 │  (position) │   │ orientation │   │  (ARCore)   │
 └──────┬──────┘   └──────┬──────┘   └──────┬──────┘
        │                 │                 │
        └────────┬────────┴────────┬────────┘
                 ▼                 ▼
        ┌────────────────────────────────┐
        │      Positioning / geometry     │   ← single processing stage:
        │  user position + bearing +      │     bearing & distance to each
        │  distance to each building      │     stored campus building
        └───────────────┬────────────────┘
                        │
          ┌─────────────┴─────────────┐
          ▼                           ▼
   ┌──────────────┐            ┌──────────────┐
   │   MAP MODE   │            │   AR MODE    │   ← two complementary
   │ (OSM + pins) │            │ (ARCore +    │     navigation modes
   │              │            │  HUD arrow)  │
   └──────────────┘            └──────────────┘
```

*Figure 1: High-level system architecture of the AR campus navigation application.*

### 6.1 Technical stack
| Layer | Choice | Rationale |
|---|---|---|
| App framework | **Flutter** (Android target) | Single professional UI codebase, fast iteration |
| Map engine | **flutter_map + OpenStreetMap** | No API key, no billing, works on first launch — best fit for "just open and use" |
| AR engine | **Native ARCore** (`com.google.ar:core`) via Flutter `PlatformView` | First-party, buildable on modern Gradle, real plane detection |
| Location | **geolocator** | GPS position + accuracy |
| Orientation | **flutter_compass** | Device heading for bearing/arrow |
| Permissions | **permission_handler** | Runtime camera + location prompts |

### 6.2 AR implementation notes
- AR mode is delivered as a native Kotlin `PlatformView` hosting an ARCore `Session` with
  horizontal-plane detection and an OpenGL renderer (camera background + detected planes +
  world-anchored marker).
- The directional **arrow, distance and turn instruction** are rendered as a Flutter overlay
  on top of the camera view, driven by GPS bearing and the device compass heading.
- ARCore is declared **AR Optional** so the app installs on all devices; AR availability is
  checked at runtime and Map mode remains fully functional on non-AR devices.

---

## 7. Functional Requirements

### 7.1 Home / Mode selection
- FR-1: On launch, show a home screen offering **Map mode** and **AR mode** with no login.
- FR-2: Surface location/camera permission state and a clear call-to-action to enable them.

### 7.2 Map mode
- FR-3: Render an interactive map centred on THM Friedberg.
- FR-4: Show the user's live position marker, updating as the user moves.
- FR-5: Render every main building as a labelled, tappable marker.
- FR-6: On marker/building tap, show a detail sheet: name, code, category, distance, bearing.
- FR-7: Provide a "Navigate in AR" action that opens AR mode targeting that building.
- FR-8: Provide a recenter-on-me control and a building list/search entry point.

### 7.3 AR camera mode
- FR-9: Request camera permission, then start an ARCore session with plane detection.
- FR-10: Show the live camera feed with detected planes visualised.
- FR-11: Overlay a large directional arrow pointing toward the selected building.
- FR-12: Overlay the live distance (metres) and a turn instruction.
- FR-13: Allow switching the target building from within AR mode.
- FR-14: Gracefully degrade with a clear message if ARCore/camera is unavailable, offering
  a path back to Map mode.

### 7.4 Cross-cutting
- FR-15: No account, login, registration, ads, or tracking SDKs.
- FR-16: Handle permission denial with clear, actionable UI (deep-link to settings).
- FR-17: Work offline for AR/bearing logic; map tiles require connectivity.

---

## 8. Non-Functional Requirements

- **Performance:** AR view targets a smooth camera preview; UI stays responsive.
- **Compatibility:** minSdk 24+, targetSdk = current Play requirement; AR Optional.
- **Privacy:** GPS and camera used only on-device for navigation; **no data leaves the
  device**, no analytics, no ad IDs. (See §10.)
- **Accessibility:** high-contrast HUD, large touch targets, readable typography.
- **Resilience:** never crash on denied permissions or missing sensors — degrade clearly.
- **Localization-ready:** English default; strings structured for future German localization.

---

## 9. UX / UI Requirements

- Professional, modern Material 3 design with a THM-inspired accent palette.
- Light & dark theme support.
- Home screen with clear, iconographic mode cards and live permission/status hints.
- Map mode: floating controls, animated building info bottom sheet, distance chips.
- AR mode: minimal, glanceable HUD — big arrow, distance, turn text, target selector.
- Consistent motion, elevation and spacing; no placeholder or debug UI in release.

---

## 10. Privacy, Compliance & Play Store Readiness

- **No login/registration**; the app is immediately usable.
- **Permissions requested & justified:**
  - `CAMERA` — required for AR camera navigation.
  - `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` — required to show position and compute
    bearing/distance to buildings.
  - `INTERNET` — required to load OpenStreetMap tiles.
- **Data safety:** no personal data collected, stored off-device, or shared. Location and
  camera are processed on-device in real time and never transmitted.
- **ARCore:** distributed via Google Play Services for AR; declared AR Optional and
  availability-checked at runtime.
- **Content & ads:** no ads, no third-party tracking, suitable for all audiences.
- **OSM attribution** displayed as required by the OpenStreetMap tile usage policy.
- Release build is minified/shrunk, signed, and ships as an Android App Bundle for Play.

---

## 11. Campus Building Data

Buildings are stored on-device as a typed dataset (code, name, category, latitude,
longitude, optional description). The dataset covers the THM Friedberg campus buildings
(Wilhelm-Leuschner-Straße 13, 61169 Friedberg) using the real building codes A1–A8, B1–B2,
C1 and the Mensa. Codes and coordinates are sourced from the OpenStreetMap mapping of the
campus (building centroids); the data layer is structured so any building can be refined in
one place without code changes elsewhere.

---

## 12. Milestones

| Milestone | Deliverable |
|---|---|
| M1 | Project scaffold, theme, data layer, services |
| M2 | Map mode complete (position + building markers + detail sheet) |
| M3 | AR mode complete (ARCore plane detection + directional HUD) |
| M4 | Play Store hardening (permissions, manifest, icon, release build) |
| M5 | Field verification of coordinates & AR on a physical device (outlook) |

---

## 13. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| GPS drift near buildings | Show accuracy, use bearing-based guidance, allow re-select |
| Compass interference | Advise figure-8 calibration; smooth heading |
| Device lacks ARCore | AR Optional + runtime check; Map mode always available |
| Approximate coordinates | Centralised data layer; flagged for field survey |
| Map tile availability | Respect OSM usage policy; graceful offline messaging |

---

## 14. Future Outlook (not committed)

- Indoor navigation for specific floors and rooms after reaching a building.
- Footpath-aware routing instead of straight-line bearing.
- German/English localization and voice guidance.
