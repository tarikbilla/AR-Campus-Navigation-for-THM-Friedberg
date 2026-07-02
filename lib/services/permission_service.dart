import 'package:permission_handler/permission_handler.dart';

/// Thin wrapper around [permission_handler] for the two permissions this app
/// needs: location (map + bearing) and camera (AR mode).
class PermissionService {
  const PermissionService();

  Future<bool> hasLocation() async {
    final status = await Permission.locationWhenInUse.status;
    return status.isGranted || status.isLimited;
  }

  Future<bool> hasCamera() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  /// Requests location permission; returns true if granted.
  Future<bool> requestLocation() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted || status.isLimited;
  }

  /// Requests camera permission; returns true if granted.
  Future<bool> requestCamera() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// True when the OS reports the permission as permanently denied and the
  /// only way forward is the app settings screen.
  Future<bool> isLocationPermanentlyDenied() =>
      Permission.locationWhenInUse.isPermanentlyDenied;

  Future<bool> isCameraPermanentlyDenied() =>
      Permission.camera.isPermanentlyDenied;

  Future<bool> openSettings() => openAppSettings();
}
