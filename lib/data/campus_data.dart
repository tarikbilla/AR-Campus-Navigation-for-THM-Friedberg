import 'package:latlong2/latlong.dart';

import 'models/campus_building.dart';

/// On-device dataset of the main THM Friedberg campus buildings.
///
/// Coordinates are approximate and clustered around the campus centre. They are
/// intended to be field-verified / GPS-surveyed before a production release.
/// Keeping the data here means positions can be corrected in a single place
/// without touching any UI or logic code.
class CampusData {
  CampusData._();

  static const List<CampusBuilding> buildings = [
    CampusBuilding(
      id: 'a',
      code: 'A',
      name: 'Main Building (Hauptgebäude)',
      category: BuildingCategory.admin,
      location: LatLng(50.33802, 8.75214),
      description:
          'Central entrance, administration and student services (StudierendenService).',
    ),
    CampusBuilding(
      id: 'b',
      code: 'B',
      name: 'Lecture Halls (Hörsaalgebäude)',
      category: BuildingCategory.lecture,
      location: LatLng(50.33769, 8.75288),
      description: 'Main lecture halls and seminar rooms.',
    ),
    CampusBuilding(
      id: 'audimax',
      code: 'AM',
      name: 'Audimax',
      category: BuildingCategory.lecture,
      location: LatLng(50.33745, 8.75201),
      description: 'Largest auditorium, used for big lectures and events.',
    ),
    CampusBuilding(
      id: 'library',
      code: 'BIB',
      name: 'Library (Bibliothek)',
      category: BuildingCategory.library,
      location: LatLng(50.33818, 8.75285),
      description: 'Campus library and quiet study spaces.',
    ),
    CampusBuilding(
      id: 'c',
      code: 'C',
      name: 'Computer Science (Informatik)',
      category: BuildingCategory.lab,
      location: LatLng(50.33742, 8.75320),
      description: 'Computer science labs and faculty offices.',
    ),
    CampusBuilding(
      id: 'd',
      code: 'D',
      name: 'Engineering Labs (Ingenieurlabore)',
      category: BuildingCategory.lab,
      location: LatLng(50.33705, 8.75258),
      description: 'Electrical and mechanical engineering laboratories.',
    ),
    CampusBuilding(
      id: 'mensa',
      code: 'Mensa',
      name: 'Cafeteria (Mensa)',
      category: BuildingCategory.dining,
      location: LatLng(50.33835, 8.75180),
      description: 'Student cafeteria and coffee bar.',
    ),
    CampusBuilding(
      id: 'sport',
      code: 'SH',
      name: 'Sports Hall (Sporthalle)',
      category: BuildingCategory.sports,
      location: LatLng(50.33690, 8.75330),
      description: 'Gymnasium and sports facilities.',
    ),
    CampusBuilding(
      id: 'workshop',
      code: 'W',
      name: 'Workshops (Werkstätten)',
      category: BuildingCategory.facility,
      location: LatLng(50.33760, 8.75360),
      description: 'Technical workshops and prototyping facilities.',
    ),
    CampusBuilding(
      id: 'verwaltung',
      code: 'V',
      name: 'Administration Annex (Verwaltung)',
      category: BuildingCategory.admin,
      location: LatLng(50.33812, 8.75150),
      description: 'Additional administrative and examination offices.',
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
