import 'package:flutter/services.dart';

import '../core/constants/app_info.dart';

/// Result of an ARCore availability check on the device.
enum ArAvailability {
  /// ARCore is supported and Google Play Services for AR is installed.
  ready,

  /// The device supports ARCore but the AR service is missing or out of date
  /// (it can be installed/updated on demand).
  needsInstall,

  /// The device does not support ARCore.
  unsupported,

  /// Availability could not be determined (still checking or an error).
  unknown,
}

/// Bridges to the native ARCore availability check so the Flutter UI can decide
/// whether to offer AR mode and show accurate messaging.
class ArAvailabilityService {
  const ArAvailabilityService();

  static const MethodChannel _channel = MethodChannel(AppInfo.arChannel);

  Future<ArAvailability> check() async {
    try {
      final String? status =
          await _channel.invokeMethod<String>('checkAvailability');
      switch (status) {
        case 'ready':
          return ArAvailability.ready;
        case 'needsInstall':
          return ArAvailability.needsInstall;
        case 'unsupported':
          return ArAvailability.unsupported;
        default:
          return ArAvailability.unknown;
      }
    } on PlatformException {
      return ArAvailability.unknown;
    } on MissingPluginException {
      return ArAvailability.unknown;
    }
  }

  /// Asks Google Play Services for AR to install/update itself.
  /// Returns true if AR is ready afterwards.
  Future<bool> requestInstall() async {
    try {
      final bool? installed =
          await _channel.invokeMethod<bool>('requestInstall');
      return installed ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
