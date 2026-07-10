import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_info.dart';

/// Live status reported by the native ARCore session.
class ArStatus {
  const ArStatus({
    required this.trackingState,
    required this.planeCount,
  });

  /// One of: 'initializing', 'tracking', 'paused', 'stopped'.
  final String trackingState;

  /// Number of horizontal planes ARCore has detected so far.
  final int planeCount;

  bool get isTracking => trackingState == 'tracking';
  bool get hasPlanes => planeCount > 0;

  static const ArStatus initial =
      ArStatus(trackingState: 'initializing', planeCount: 0);
}

/// Imperative handle to the native ARCore view: pushes the walking route and
/// live device pose (GPS + heading) so the native side can draw the path on the
/// ground, geo-aligned to the real world.
class ArViewController {
  ArViewController._(this._channel);

  final MethodChannel _channel;

  /// Sends the full route polyline (origin→destination) plus the destination.
  Future<void> setRoute(List<LatLng> points, LatLng destination) {
    return _invoke('setRoute', {
      'points': [
        for (final p in points) [p.latitude, p.longitude],
      ],
      'destLat': destination.latitude,
      'destLng': destination.longitude,
    });
  }

  /// Streams the latest device position + compass heading (degrees from north).
  Future<void> updatePose({
    required double lat,
    required double lng,
    required double heading,
    double accuracy = 0,
  }) {
    return _invoke('updatePose', {
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'accuracy': accuracy,
    });
  }

  /// Streams the textual guidance drawn as 3D labels in the scene: the distance
  /// and step count remaining, and the destination name shown on the beacon.
  Future<void> updateGuidance({
    required String distanceText,
    required String stepsText,
    required String etaText,
    required String destName,
  }) {
    return _invoke('updateGuidance', {
      'distanceText': distanceText,
      'stepsText': stepsText,
      'etaText': etaText,
      'destName': destName,
    });
  }

  Future<void> clearRoute() => _invoke('clearRoute', null);

  Future<void> _invoke(String method, Object? args) async {
    try {
      await _channel.invokeMethod(method, args);
    } on PlatformException {
      // Native side may not be ready yet; safe to ignore transient failures.
    } on MissingPluginException {
      // View detached.
    }
  }
}

/// Hosts the native ARCore camera / plane-detection / route view using Android
/// hybrid composition (required for a smooth camera + OpenGL surface).
class ArCameraView extends StatefulWidget {
  const ArCameraView({
    super.key,
    this.onStatus,
    this.onControllerCreated,
  });

  final ValueChanged<ArStatus>? onStatus;
  final ValueChanged<ArViewController>? onControllerCreated;

  @override
  State<ArCameraView> createState() => _ArCameraViewState();
}

class _ArCameraViewState extends State<ArCameraView> {
  MethodChannel? _channel;

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const String viewType = AppInfo.arViewType;
    return PlatformViewLink(
      viewType: viewType,
      surfaceFactory: (context, controller) {
        return AndroidViewSurface(
          controller: controller as AndroidViewController,
          gestureRecognizers:
              const <Factory<OneSequenceGestureRecognizer>>{},
          hitTestBehavior: PlatformViewHitTestBehavior.opaque,
        );
      },
      onCreatePlatformView: (params) {
        final controller = PlatformViewsService.initExpensiveAndroidView(
          id: params.id,
          viewType: viewType,
          layoutDirection: TextDirection.ltr,
          creationParams: const <String, dynamic>{},
          creationParamsCodec: const StandardMessageCodec(),
          onFocus: () => params.onFocusChanged(true),
        )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
          ..create();
        return controller;
      },
    );
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('${AppInfo.arChannel}/view_$id');
    channel.setMethodCallHandler(_handleCall);
    _channel = channel;
    widget.onControllerCreated?.call(ArViewController._(channel));
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    if (call.method == 'status') {
      final map = (call.arguments as Map).cast<String, dynamic>();
      widget.onStatus?.call(
        ArStatus(
          trackingState: map['trackingState'] as String? ?? 'initializing',
          planeCount: (map['planeCount'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return null;
  }
}
