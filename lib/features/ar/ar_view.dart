import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

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

/// Hosts the native ARCore camera/plane-detection view using Android hybrid
/// composition (required for a smooth camera + OpenGL surface).
class ArCameraView extends StatefulWidget {
  const ArCameraView({super.key, this.onStatus});

  final ValueChanged<ArStatus>? onStatus;

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
