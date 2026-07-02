import 'package:latlong2/latlong.dart';

/// A walking route between two points: an ordered polyline plus its total
/// distance and estimated duration.
class WalkingRoute {
  const WalkingRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isFallback,
  });

  /// Ordered geographic points from origin to destination.
  final List<LatLng> points;

  final double distanceMeters;
  final double durationSeconds;

  /// True when this is a straight-line estimate (routing was unavailable).
  final bool isFallback;

  LatLng get origin => points.first;
  LatLng get destination => points.last;

  /// Estimated walking time, e.g. "5 min".
  String get etaLabel {
    final int minutes = (durationSeconds / 60).round();
    if (minutes < 1) return '<1 min';
    if (minutes < 60) return '$minutes min';
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }
}
