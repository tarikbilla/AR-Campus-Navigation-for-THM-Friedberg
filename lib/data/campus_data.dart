import 'package:latlong2/latlong.dart';

import 'models/campus_building.dart';

/// On-device dataset of the THM Friedberg campus buildings.
///
/// Campus: Wilhelm-Leuschner-Straße 13, 61169 Friedberg (Hessen).
/// Building codes and coordinates are sourced from the OpenStreetMap mapping of
/// the THM Friedberg campus (building centroids), so map and AR guidance point
/// at the real buildings. They can be corrected in this single file without
/// touching any UI or logic code.
class CampusData {
  CampusData._();

  static const List<CampusBuilding> buildings = [
    CampusBuilding(
      id: 'a1',
      code: 'A1',
      name: 'A1 – Audimax',
      category: BuildingCategory.lecture,
      location: LatLng(50.3304588, 8.7593124),
      description:
          'Audimax — the largest auditorium, used for major lectures and events.',
    ),
    CampusBuilding(
      id: 'a2',
      code: 'A2',
      name: 'A2',
      category: BuildingCategory.lecture,
      location: LatLng(50.3299985, 8.7592217),
      description: 'Lecture halls, seminar rooms and faculty offices.',
    ),
    CampusBuilding(
      id: 'a3',
      code: 'A3',
      name: 'A3',
      category: BuildingCategory.lecture,
      location: LatLng(50.3301716, 8.7586823),
      description: 'Lecture halls, seminar rooms and faculty offices.',
    ),
    CampusBuilding(
      id: 'a4',
      code: 'A4',
      name: 'A4',
      category: BuildingCategory.lecture,
      location: LatLng(50.3305911, 8.7587002),
      description: 'Lecture halls, seminar rooms and faculty offices.',
    ),
    CampusBuilding(
      id: 'a5',
      code: 'A5',
      name: 'A5',
      category: BuildingCategory.lecture,
      location: LatLng(50.3295968, 8.7583034),
      description: 'Lecture halls, seminar rooms and student services.',
    ),
    CampusBuilding(
      id: 'a6',
      code: 'A6',
      name: 'A6 – Mensa',
      category: BuildingCategory.dining,
      location: LatLng(50.3300014, 8.7581087),
      description: 'Mensa — student cafeteria and dining.',
    ),
    CampusBuilding(
      id: 'a7',
      code: 'A7',
      name: 'A7',
      category: BuildingCategory.lab,
      location: LatLng(50.3303380, 8.7578871),
      description: 'Faculty offices and laboratories.',
    ),
    CampusBuilding(
      id: 'a8',
      code: 'A8',
      name: 'A8',
      category: BuildingCategory.lab,
      location: LatLng(50.3301427, 8.7572974),
      description: 'Faculty offices and laboratories.',
    ),
    CampusBuilding(
      id: 'b1',
      code: 'B1',
      name: 'B1',
      category: BuildingCategory.facility,
      location: LatLng(50.3313741, 8.7596245),
      description: 'Departmental offices, labs and seminar rooms.',
    ),
    CampusBuilding(
      id: 'b2',
      code: 'B2',
      name: 'B2',
      category: BuildingCategory.facility,
      location: LatLng(50.3316722, 8.7603046),
      description: 'Departmental offices, labs and seminar rooms.',
    ),
    CampusBuilding(
      id: 'c1',
      code: 'C1',
      name: 'C1',
      category: BuildingCategory.facility,
      location: LatLng(50.3279030, 8.7562370),
      description: 'Additional teaching and departmental building.',
    ),
  ];

  static CampusBuilding? byId(String? id) {
    if (id == null) return null;
    for (final b in buildings) {
      if (b.id == id) return b;
    }
    return null;
  }
}
