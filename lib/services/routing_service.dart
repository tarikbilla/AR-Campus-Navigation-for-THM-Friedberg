import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/utils/geo_utils.dart';
import '../data/models/walking_route.dart';
import 'campus_router.dart';

/// Produces walking routes for the app. Inside the THM Friedberg campus it
/// routes over the on-device [CampusRouter] pedestrian graph, so directions
/// follow the real internal lanes (which OpenStreetMap does not fully map).
/// Outside campus it uses the keyless OSRM foot service, and falls back to a
/// straight-line estimate when neither is available — so the app keeps working
/// offline / without any API key.
class RoutingService {
  RoutingService();

  static const String _base =
      'https://routing.openstreetmap.de/routed-foot/route/v1/foot';
  static const Duration _timeout = Duration(seconds: 12);
  static const double _walkingSpeedMps = 1.35; // ~4.9 km/h

  // Campus bounding box (building extents + ~250 m margin). When the origin is
  // inside it, the local campus graph gives better path-following than OSRM.
  static const double _minLat = 50.3255;
  static const double _maxLat = 50.3340;
  static const double _minLng = 8.7538;
  static const double _maxLng = 8.7628;

  final CampusRouter _campusRouter = const CampusRouter();
  final Map<String, WalkingRoute> _cache = {};

  /// Returns a walking route from [origin] to [destination]. Results are cached
  /// per rounded origin + destination so small GPS jitter reuses the same route.
  Future<WalkingRoute> route(LatLng origin, LatLng destination) async {
    final key = _cacheKey(origin, destination);
    final cached = _cache[key];
    if (cached != null) return cached;

    // 1) On-campus: follow the internal walking-lane network locally.
    if (_isOnCampus(origin)) {
      final campus = _campusRouter.route(origin, destination);
      if (campus != null) {
        _cache[key] = campus;
        return campus;
      }
    }

    // 2) Off-campus: fall back to the online OSRM foot service.
    try {
      final uri = Uri.parse(
        '$_base/${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&steps=false',
      );
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode == 200) {
        final route = _parse(resp.body, origin, destination);
        if (route != null) {
          _cache[key] = route;
          return route;
        }
      }
    } catch (_) {
      // Fall through to a straight-line estimate.
    }

    final fallback = _straightLine(origin, destination);
    _cache[key] = fallback;
    return fallback;
  }

  WalkingRoute? _parse(String body, LatLng origin, LatLng destination) {
    final Map<String, dynamic> json =
        jsonDecode(body) as Map<String, dynamic>;
    if (json['code'] != 'Ok') return null;
    final routes = json['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return null;

    final route = routes.first as Map<String, dynamic>;
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coords = geometry['coordinates'] as List<dynamic>;

    final points = <LatLng>[
      for (final c in coords)
        LatLng((c as List)[1] as double, c[0] as double),
    ];
    if (points.length < 2) return null;

    return WalkingRoute(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
      isFallback: false,
    );
  }

  WalkingRoute _straightLine(LatLng origin, LatLng destination) {
    final distance = GeoUtils.distanceMeters(origin, destination);
    return WalkingRoute(
      points: [origin, destination],
      distanceMeters: distance,
      durationSeconds: distance / _walkingSpeedMps,
      isFallback: true,
    );
  }

  bool _isOnCampus(LatLng p) =>
      p.latitude >= _minLat &&
      p.latitude <= _maxLat &&
      p.longitude >= _minLng &&
      p.longitude <= _maxLng;

  String _cacheKey(LatLng o, LatLng d) {
    String r(double v) => v.toStringAsFixed(4); // ~11 m buckets
    return '${r(o.latitude)},${r(o.longitude)}->${r(d.latitude)},${r(d.longitude)}';
  }
}
