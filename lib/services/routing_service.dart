import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/utils/geo_utils.dart';
import '../data/models/walking_route.dart';

/// Fetches walking routes along real footpaths using the keyless OSRM foot
/// service (the same routing backend used by openstreetmap.org). Falls back to
/// a straight line when routing is unavailable, so the app keeps working
/// offline / without any API key.
class RoutingService {
  RoutingService();

  static const String _base =
      'https://routing.openstreetmap.de/routed-foot/route/v1/foot';
  static const Duration _timeout = Duration(seconds: 12);
  static const double _walkingSpeedMps = 1.35; // ~4.9 km/h

  final Map<String, WalkingRoute> _cache = {};

  /// Returns a walking route from [origin] to [destination]. Results are cached
  /// per rounded origin + destination so small GPS jitter reuses the same route.
  Future<WalkingRoute> route(LatLng origin, LatLng destination) async {
    final key = _cacheKey(origin, destination);
    final cached = _cache[key];
    if (cached != null) return cached;

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

  String _cacheKey(LatLng o, LatLng d) {
    String r(double v) => v.toStringAsFixed(4); // ~11 m buckets
    return '${r(o.latitude)},${r(o.longitude)}->${r(d.latitude)},${r(d.longitude)}';
  }
}
