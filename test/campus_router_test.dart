import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:thmcampusnav/core/utils/geo_utils.dart';
import 'package:thmcampusnav/data/campus_data.dart';
import 'package:thmcampusnav/data/campus_paths.dart';
import 'package:thmcampusnav/services/campus_router.dart';

void main() {
  const router = CampusRouter();

  double routeLength(List<LatLng> pts) {
    double m = 0;
    for (int i = 1; i < pts.length; i++) {
      m += GeoUtils.distanceMeters(pts[i - 1], pts[i]);
    }
    return m;
  }

  /// Minimum distance (m) from [p] to any real footpath segment.
  double distanceToNetwork(LatLng p) {
    final double mPerLat = 111320.0;
    final double mPerLng = 111320.0 * math.cos(p.latitude * math.pi / 180.0);
    double px(LatLng q) => (q.longitude - p.longitude) * mPerLng;
    double py(LatLng q) => (q.latitude - p.latitude) * mPerLat;
    double best = double.infinity;
    for (final lane in CampusPaths.footways) {
      for (int i = 1; i < lane.length; i++) {
        final ax = px(lane[i - 1]), ay = py(lane[i - 1]);
        final dx = px(lane[i]) - ax, dy = py(lane[i]) - ay;
        final len2 = dx * dx + dy * dy;
        double t = 0;
        if (len2 > 0) t = (((-ax) * dx + (-ay) * dy) / len2).clamp(0.0, 1.0);
        final sx = ax + dx * t, sy = ay + dy * t;
        best = math.min(best, math.sqrt(sx * sx + sy * sy));
      }
    }
    return best;
  }

  test('network imported from OpenStreetMap and connected', () {
    expect(CampusPaths.footways.length, greaterThan(100));
    expect(CampusPaths.nodes.length, greaterThan(400));
    // Most nodes belong to one big connected component.
    expect(CampusPaths.routableNodes.length,
        greaterThan(CampusPaths.nodes.length * 0.7));
  });

  test('every building is reachable on the real lane graph', () {
    const origin = LatLng(50.330200, 8.758550); // central campus point
    for (final b in CampusData.buildings) {
      final r = router.route(origin, b.location);
      expect(r, isNotNull, reason: '${b.code} should be reachable');
      expect(r!.isFallback, isFalse, reason: '${b.code} routed on the graph');
      expect(r.points.first, origin);
      expect(GeoUtils.distanceMeters(r.points.last, b.location), lessThan(1.0));
    }
  });

  test('route interior follows the real footpaths (on-lane)', () {
    final a8 = CampusData.byId('a8')!.location;
    final a1 = CampusData.byId('a1')!.location;
    final r = router.route(a8, a1)!;

    // It bends along the network rather than cutting straight across (the
    // straight line would run through the A-block buildings), so the walked
    // distance is legitimately longer — but still a sane campus distance.
    expect(r.points.length, greaterThan(4));
    final straight = GeoUtils.distanceMeters(a8, a1);
    final along = routeLength(r.points);
    expect(along, greaterThan(straight));
    expect(along, lessThan(700));

    // Every interior vertex (excluding the building endpoints) lies on a lane.
    for (int i = 1; i < r.points.length - 1; i++) {
      expect(distanceToNetwork(r.points[i]), lessThan(1.0),
          reason: 'point $i should sit on a footpath');
    }
  });

  test('an off-lane origin snaps onto the network', () {
    const off = LatLng(50.330650, 8.758600); // a little off the paths
    final a3 = CampusData.byId('a3')!.location;
    final r = router.route(off, a3)!;
    expect(r.points.first, off); // starts exactly at the user
    // The second point (the snap) is on a lane and close to the user.
    expect(distanceToNetwork(r.points[1]), lessThan(1.0));
    expect(GeoUtils.distanceMeters(off, r.points[1]), lessThan(60.0));
  });
}
