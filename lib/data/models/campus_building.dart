import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// Category of a campus building, used for iconography and grouping.
enum BuildingCategory {
  lecture('Lecture & Halls', Icons.school_outlined),
  lab('Labs & Workshops', Icons.science_outlined),
  library('Library', Icons.local_library_outlined),
  dining('Dining', Icons.restaurant_outlined),
  admin('Administration', Icons.badge_outlined),
  sports('Sports', Icons.sports_handball_outlined),
  facility('Facilities', Icons.apartment_outlined);

  const BuildingCategory(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// An immutable campus building with its geographic position.
@immutable
class CampusBuilding {
  const CampusBuilding({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    required this.location,
    this.description,
  });

  /// Stable identifier (used for selection and navigation state).
  final String id;

  /// Short campus code shown on markers, e.g. "A", "B1", "Mensa".
  final String code;

  /// Full human-readable name.
  final String name;

  final BuildingCategory category;

  /// Geographic position of the building's main entrance.
  final LatLng location;

  final String? description;

  double get latitude => location.latitude;
  double get longitude => location.longitude;
}
