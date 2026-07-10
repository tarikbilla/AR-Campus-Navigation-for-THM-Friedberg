import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../data/campus_paths.dart';
import '../../../data/models/walking_route.dart';

/// A faint dashed layer that reveals the *entire* campus walking-lane network
/// (the real OpenStreetMap footpaths), not just the routed path — so users can
/// see every small path on campus. It draws exactly the [CampusPaths.footways]
/// geometry, so it lines up with the dashed paths on the map tiles. Drawn
/// beneath the active route.
Widget buildCampusLanesLayer(ColorScheme scheme) {
  return PolylineLayer(
    polylines: [
      for (final lane in CampusPaths.footways)
        Polyline(
          points: lane,
          strokeWidth: 3,
          color: scheme.primary.withValues(alpha: 0.30),
          pattern: StrokePattern.dashed(segments: const [5, 7]),
          strokeCap: StrokeCap.round,
        ),
    ],
  );
}

/// Builds the flutter_map layers that visualise a walking [WalkingRoute]:
/// a casing + gradient line, a flowing wave of direction chevrons, and
/// origin / destination markers.
///
/// Every animated element animates *itself* (its own controller), so the map
/// widget tree never has to rebuild for the animation — this keeps gestures
/// (pinch-zoom / pan) smooth and crash-free.
List<Widget> buildRouteLayers({
  required WalkingRoute route,
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
          gradientColors: const [AppColors.brand, AppColors.accent],
        ),
      ],
    ),
    MarkerLayer(markers: _chevrons(pts, cum, total)),
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
          width: 54,
          height: 60,
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
  const spacing = 26.0; // metres between chevrons
  if (total < spacing) return markers;
  int index = 0;
  final int count = ((total - 6) / spacing).floor();
  for (double d = spacing; d < total - 6; d += spacing) {
    final p = _pointAtDistance(pts, cum, d);
    final ahead = _pointAtDistance(pts, cum, math.min(d + 4, total));
    final bearing = GeoUtils.bearingDegrees(p, ahead);
    final double phase = count <= 0 ? 0 : index / count;
    markers.add(
      Marker(
        point: p,
        width: 22,
        height: 22,
        child: _FlowChevron(bearingDeg: bearing, phase: phase),
      ),
    );
    index++;
  }
  return markers;
}

/// A single direction chevron that brightens as a wave sweeps along the route
/// from origin to destination, giving a sense of forward flow.
class _FlowChevron extends StatefulWidget {
  const _FlowChevron({required this.bearingDeg, required this.phase});

  final double bearingDeg;
  final double phase; // 0 at origin .. 1 at destination

  @override
  State<_FlowChevron> createState() => _FlowChevronState();
}

class _FlowChevronState extends State<_FlowChevron>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: widget.bearingDeg * math.pi / 180.0,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Distance of this chevron's phase from the travelling wave head.
          double d = (_controller.value - widget.phase).abs();
          d = math.min(d, 1 - d);
          final double glow = math.max(0.0, 1 - d * 5);
          final double opacity = 0.35 + 0.65 * glow;
          final double scale = 0.85 + 0.35 * glow;
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Icon(
                Icons.navigation,
                size: 16,
                color: Color.lerp(Colors.white, AppColors.accent, glow),
                shadows: const [
                  Shadow(color: Colors.black45, blurRadius: 3),
                ],
              ),
            ),
          );
        },
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

/// Destination marker with a self-animating pulse ring.
class _DestinationFlag extends StatefulWidget {
  const _DestinationFlag();

  @override
  State<_DestinationFlag> createState() => _DestinationFlagState();
}

class _DestinationFlagState extends State<_DestinationFlag>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final double t = _controller.value;
            return Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: (1 - t) * 0.5,
                  child: Container(
                    width: 20 + t * 22,
                    height: 20 + t * 22,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                child!,
              ],
            );
          },
          child: Container(
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
        ),
        Container(width: 2, height: 8, color: Colors.white),
      ],
    );
  }
}
