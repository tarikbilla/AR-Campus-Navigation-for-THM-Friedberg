import 'dart:async';

import 'package:flutter_compass/flutter_compass.dart';

/// Wraps [flutter_compass] to provide a smoothed device heading stream in
/// degrees (0–360, clockwise from magnetic/true north as reported by the OS).
///
/// A small low-pass filter reduces the jitter typical of magnetometer data so
/// the AR arrow and map orientation feel stable.
class CompassService {
  CompassService();

  double? _smoothed;

  /// True if the platform exposes compass events at all.
  bool get isSupported => FlutterCompass.events != null;

  Stream<double> stream() {
    final events = FlutterCompass.events;
    if (events == null) {
      return const Stream.empty();
    }
    return events
        .map((e) => e.heading)
        .where((h) => h != null)
        .map((h) => _smooth(h!));
  }

  double _smooth(double heading) {
    final double normalized = (heading + 360.0) % 360.0;
    final double? prev = _smoothed;
    if (prev == null) {
      _smoothed = normalized;
      return normalized;
    }
    // Interpolate on the shortest arc to avoid the 359°→0° jump.
    double delta = ((normalized - prev + 540.0) % 360.0) - 180.0;
    const double alpha = 0.15; // smoothing factor
    final double next = (prev + alpha * delta + 360.0) % 360.0;
    _smoothed = next;
    return next;
  }
}
