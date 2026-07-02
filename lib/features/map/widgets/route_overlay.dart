import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../data/models/walking_route.dart';

/// Builds the flutter_map layers that visualise a walking [WalkingRoute]:
/// a casing + gradient line, direction chevrons, an animated "comet" that
/// travels the path, and origin / destination markers.
List<Widget> buildRouteLayers({
  required WalkingRoute route,
  required double flow, // 0..1 animation phase
  required ColorScheme scheme,
}) {
  final pts = route.points;
  final cum = _cumulative(pts);
  final total = cum.isEmpty ? 0.0 : cum.last;

  return [
    PolylineLayer(
      polylines: [
        Polyline(
          points: pts,
          strokeWidth: 8,
          borderStrokeWidth: 3,
          borderColor: Colors.white,
          gradientColors: [AppColors.brand, AppColors.accent],
        ),
      ],
    ),
    MarkerLayer(markers: _chevrons(pts, cum, total)),
    if (total > 0)
      MarkerLayer(
        markers: [
          _comet(pts, cum, total, flow),
        ],
      ),
    MarkerLayer(
      markers: [
        Marker(
          point: route.origin,
          width: 22,
          height: 22,
          child: const _OriginDot(),
        ),
        Marker(
          point: route.destination,
          width: 40,
          height: 46,
          alignment: Alignment.topCenter,
          child: const _DestinationFlag(),
        ),
      ],
    ),
  ];
}

List<double> _cumulative(List<LatLng> pts) {
  final out = <double>[];
  double acc = 0;
  for (int i = 0; i < pts.length; i++) {
    if (i > 0) acc += GeoUtils.distanceMeters(pts[i - 1], pts[i]);
    out.add(acc);
  }
  return out;
}

LatLng _pointAtDistance(List<LatLng> pts, List<double> cum, double d) {
  if (d <= 0) return pts.first;
  if (d >= cum.last) return pts.last;
  for (int i = 1; i < pts.length; i++) {
    if (cum[i] >= d) {
      final segLen = cum[i] - cum[i - 1];
      final t = segLen == 0 ? 0.0 : (d - cum[i - 1]) / segLen;
      return LatLng(
        pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * t,
        pts[i - 1].longitude + (pts[i].longitude - pts[i - 1].longitude) * t,
      );
    }
  }
  return pts.last;
}

List<Marker> _chevrons(List<LatLng> pts, List<double> cum, double total) {
  final markers = <Marker>[];
  const spacing = 28.0; // metres between chevrons
  if (total < spacing) return markers;
  for (double d = spacing; d < total - 6; d += spacing) {
    final p = _pointAtDistance(pts, cum, d);
    final ahead = _pointAtDistance(pts, cum, math.min(d + 4, total));
    final bearing = GeoUtils.bearingDegrees(p, ahead);
    markers.add(
      Marker(
        point: p,
        width: 20,
        height: 20,
        child: Transform.rotate(
          angle: bearing * math.pi / 180.0,
          child: const Icon(Icons.navigation, size: 15, color: Colors.white),
        ),
      ),
    );
  }
  return markers;
}

Marker _comet(List<LatLng> pts, List<double> cum, double total, double flow) {
  final d = (flow % 1.0) * total;
  final p = _pointAtDistance(pts, cum, d);
  return Marker(
    point: p,
    width: 26,
    height: 26,
    child: const _CometDot(),
  );
}

class _CometDot extends StatelessWidget {
  const _CometDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.9),
            blurRadius: 12,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.accent,
          ),
        ),
      ),
    );
  }
}

class _OriginDot extends StatelessWidget {
  const _OriginDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.brand,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 5),
        ],
      ),
    );
  }
}

class _DestinationFlag extends StatelessWidget {
  const _DestinationFlag();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3), blurRadius: 6),
            ],
          ),
          child: const Icon(Icons.flag, color: Colors.white, size: 16),
        ),
        Container(width: 2, height: 10, color: Colors.white),
      ],
    );
  }
}
