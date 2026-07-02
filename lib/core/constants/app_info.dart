import 'package:latlong2/latlong.dart';

/// Static, app-wide constants and identifiers.
class AppInfo {
  AppInfo._();

  static const String appName = 'THM Campus AR';
  static const String appFullName = 'AR Campus Navigation for THM Friedberg';
  static const String tagline =
      'Find any building on the THM Friedberg campus — on the map or through your camera.';

  static const String campusName = 'THM Campus Friedberg';
  static const String campusAddress =
      'Wilhelm-Leuschner-Straße 13, 61169 Friedberg (Hessen)';

  /// Approximate geographic centre of the THM Friedberg campus.
  ///
  /// Used as the initial map camera target. Coordinates are approximate and
  /// intended to be field-verified before production release.
  static const LatLng campusCenter = LatLng(50.33780, 8.75230);

  /// Default initial map zoom over campus.
  static const double defaultMapZoom = 17.0;

  /// OpenStreetMap attribution (required by the OSM tile usage policy).
  static const String osmAttribution = '© OpenStreetMap contributors';

  /// Method-channel + platform-view identifiers shared with the native side.
  static const String arViewType = 'net.godevs.thmcampusnav/ar_view';
  static const String arChannel = 'net.godevs.thmcampusnav/ar';
}
