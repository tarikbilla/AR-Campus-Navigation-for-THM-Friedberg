import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// A single position sample with its horizontal accuracy.
class UserPosition {
  const UserPosition({
    required this.location,
    required this.accuracyMeters,
    this.headingDegrees,
    this.speedMps,
  });

  final LatLng location;
  final double accuracyMeters;

  /// GPS-derived course over ground (may be null when stationary).
  final double? headingDegrees;
  final double? speedMps;
}

/// Wraps [geolocator] to expose a simple stream of [UserPosition] updates and
/// one-shot helpers, with clear handling of the "service disabled" and
/// "permission denied" states.
class LocationService {
  LocationService();

  StreamSubscription<Position>? _sub;

  static const LocationSettings _settings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 1,
  );

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Ensures location services + permission are usable. Returns true if the app
  /// can obtain a position.
  Future<bool> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Best available last-known or current position, or null on failure.
  Future<UserPosition?> current() async {
    try {
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: _settings,
      );
      return _map(pos);
    } catch (_) {
      return null;
    }
  }

  /// Continuous stream of position updates.
  Stream<UserPosition> stream() {
    return Geolocator.getPositionStream(locationSettings: _settings)
        .map(_map);
  }

  UserPosition _map(Position pos) => UserPosition(
        location: LatLng(pos.latitude, pos.longitude),
        accuracyMeters: pos.accuracy,
        headingDegrees: pos.heading >= 0 ? pos.heading : null,
        speedMps: pos.speed >= 0 ? pos.speed : null,
      );

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
