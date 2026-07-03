import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Geographic helper functions for distance and bearing calculations.
///
/// All bearings are compass bearings in degrees, measured clockwise from true
/// north (0° = north, 90° = east, 180° = south, 270° = west).
class GeoUtils {
  GeoUtils._();

  static const double _earthRadiusMeters = 6371000.0;

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;
  static double _toDegrees(double radians) => radians * 180.0 / math.pi;

  /// Great-circle distance between two points in metres (haversine formula).
  static double distanceMeters(LatLng from, LatLng to) {
    final double lat1 = _toRadians(from.latitude);
    final double lat2 = _toRadians(to.latitude);
    final double dLat = _toRadians(to.latitude - from.latitude);
    final double dLng = _toRadians(to.longitude - from.longitude);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  /// Initial compass bearing (0–360°) from [from] to [to].
  static double bearingDegrees(LatLng from, LatLng to) {
    final double lat1 = _toRadians(from.latitude);
    final double lat2 = _toRadians(to.latitude);
    final double dLng = _toRadians(to.longitude - from.longitude);

    final double y = math.sin(dLng) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    final double bearing = _toDegrees(math.atan2(y, x));
    return (bearing + 360.0) % 360.0;
  }

  /// Smallest signed angle (-180..180) to rotate from [heading] to [bearing].
  ///
  /// Positive means the target is to the right, negative means to the left.
  static double relativeAngle(double heading, double bearing) {
    double diff = (bearing - heading + 540.0) % 360.0 - 180.0;
    return diff;
  }

  /// Human-readable distance, e.g. "12 m" or "1.4 km".
  static String formatDistance(double meters) {
    if (meters.isNaN || meters.isInfinite) return '—';
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    final double km = meters / 1000.0;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  /// Turn instruction derived from a relative angle (-180..180).
  static String turnInstruction(double relative) {
    final double a = relative.abs();
    if (a <= 15) return 'Straight ahead';
    if (a >= 160) return 'Behind you — turn around';
    final String side = relative > 0 ? 'right' : 'left';
    if (a <= 55) return 'Bear $side';
    if (a <= 125) return 'Turn $side';
    return 'Sharp $side';
  }

  /// 16-point compass label for a bearing, e.g. "NE", "SSW".
  static String compassLabel(double bearing) {
    const List<String> points = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', //
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW',
    ];
    final int index = ((bearing % 360) / 22.5).round() % 16;
    return points[index];
  }

  /// Average walking step length in metres, used to estimate a step count.
  static const double stepLengthMeters = 0.75;

  /// Estimated number of walking steps to cover [meters].
  static int stepsForMeters(double meters) {
    if (meters.isNaN || meters.isInfinite || meters <= 0) return 0;
    return (meters / stepLengthMeters).round();
  }

  /// Remaining distance (metres) from [user] to the end of the [route],
  /// measured *along* the polyline: the user is projected onto the nearest
  /// segment and the remaining segment lengths are summed. Falls back to the
  /// straight-line distance to the last point when the route is degenerate.
  static double remainingAlongRoute(List<LatLng> route, LatLng user) {
    if (route.length < 2) {
      return route.isEmpty ? 0 : distanceMeters(user, route.last);
    }

    // Local equirectangular projection (metres) centred on the user.
    final double mPerLat = 111320.0;
    final double mPerLng = 111320.0 * math.cos(_toRadians(user.latitude));
    List<double> toXY(LatLng p) => [
          (p.longitude - user.longitude) * mPerLng,
          (p.latitude - user.latitude) * mPerLat,
        ];

    double bestDist = double.infinity;
    int bestSeg = 0;
    double bestT = 0;

    for (int i = 0; i < route.length - 1; i++) {
      final a = toXY(route[i]);
      final b = toXY(route[i + 1]);
      final dx = b[0] - a[0];
      final dy = b[1] - a[1];
      final segLen2 = dx * dx + dy * dy;
      double t = 0;
      if (segLen2 > 0) {
        // Project the user (origin) onto the segment.
        t = (-a[0] * dx + -a[1] * dy) / segLen2;
        t = t.clamp(0.0, 1.0);
      }
      final px = a[0] + dx * t;
      final py = a[1] + dy * t;
      final d = math.sqrt(px * px + py * py);
      if (d < bestDist) {
        bestDist = d;
        bestSeg = i;
        bestT = t;
      }
    }

    // Remaining = partial of the current segment + all following segments.
    double remaining =
        distanceMeters(route[bestSeg], route[bestSeg + 1]) * (1 - bestT);
    for (int i = bestSeg + 1; i < route.length - 1; i++) {
      remaining += distanceMeters(route[i], route[i + 1]);
    }
    return remaining;
  }
}
