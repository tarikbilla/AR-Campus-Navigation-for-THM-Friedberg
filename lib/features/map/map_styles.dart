import 'package:flutter/material.dart';

/// A selectable base-map "mood" (tile source). All sources here are keyless and
/// free to use, keeping the app's no-account / no-API-key design.
class MapStyle {
  const MapStyle({
    required this.id,
    required this.label,
    required this.icon,
    required this.urlTemplate,
    required this.attributions,
    this.subdomains = const <String>[],
    this.maxZoom = 19,
    this.isDark = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final String urlTemplate;

  /// Attribution lines required by the tile provider (shown on the map).
  final List<String> attributions;
  final List<String> subdomains;
  final double maxZoom;

  /// True for dark base maps (lets overlays pick a contrasting treatment).
  final bool isDark;
}

/// The set of base-map layers the user can cycle through from the map.
class MapStyles {
  MapStyles._();

  static const MapStyle standard = MapStyle(
    id: 'standard',
    label: 'Standard',
    icon: Icons.map_outlined,
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    attributions: ['© OpenStreetMap contributors'],
  );

  static const MapStyle cycle = MapStyle(
    id: 'cycle',
    label: 'Cycle',
    icon: Icons.directions_bike,
    urlTemplate:
        'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    maxZoom: 20,
    attributions: ['CyclOSM', '© OpenStreetMap contributors'],
  );

  static const MapStyle satellite = MapStyle(
    id: 'satellite',
    label: 'Satellite',
    icon: Icons.satellite_alt,
    urlTemplate:
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    attributions: ['Imagery © Esri, Maxar, Earthstar Geographics'],
    isDark: true,
  );

  static const MapStyle dark = MapStyle(
    id: 'dark',
    label: 'Dark',
    icon: Icons.dark_mode_outlined,
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c', 'd'],
    maxZoom: 20,
    attributions: ['© OpenStreetMap contributors', '© CARTO'],
    isDark: true,
  );

  /// Ordered list used by the layer switcher (tap cycles through these).
  static const List<MapStyle> all = [standard, cycle, satellite, dark];
}
