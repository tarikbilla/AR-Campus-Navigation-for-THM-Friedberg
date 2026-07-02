import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/geo_utils.dart';
import '../../data/campus_data.dart';
import '../../data/models/campus_building.dart';
import '../../data/models/walking_route.dart';
import '../../services/ar_availability_service.dart';
import '../../services/compass_service.dart';
import '../../services/location_service.dart';
import '../../services/permission_service.dart';
import '../../services/routing_service.dart';
import '../../widgets/building_list_sheet.dart';
import 'ar_view.dart';
import 'widgets/ar_hud.dart';

enum _Stage { checking, cameraDenied, arUnsupported, needsInstall, ready }

/// AR camera mode: opens an ARCore session with plane detection, draws the
/// walking route on the ground and a beacon at the target building, and overlays
/// a directional arrow + distance HUD.
class ArNavigationScreen extends StatefulWidget {
  const ArNavigationScreen({super.key, this.targetBuildingId});

  final String? targetBuildingId;

  @override
  State<ArNavigationScreen> createState() => _ArNavigationScreenState();
}

class _ArNavigationScreenState extends State<ArNavigationScreen> {
  final PermissionService _permissions = const PermissionService();
  final ArAvailabilityService _ar = const ArAvailabilityService();
  final LocationService _location = LocationService();
  final CompassService _compass = CompassService();
  final RoutingService _routing = RoutingService();

  StreamSubscription<UserPosition>? _positionSub;
  StreamSubscription<double>? _headingSub;

  _Stage _stage = _Stage.checking;
  ArStatus _arStatus = ArStatus.initial;
  UserPosition? _position;
  double? _heading;
  CampusBuilding? _target;

  ArViewController? _arController;
  WalkingRoute? _route;
  bool _routeFetching = false;
  LatLng? _routeOrigin;
  String? _routeTargetId;

  @override
  void initState() {
    super.initState();
    _target = CampusData.byId(widget.targetBuildingId);
    _init();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _headingSub?.cancel();
    _location.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() => _stage = _Stage.checking);

    if (!await _permissions.hasCamera()) {
      final granted = await _permissions.requestCamera();
      if (!granted) {
        if (mounted) setState(() => _stage = _Stage.cameraDenied);
        return;
      }
    }

    final availability = await _ar.check();
    if (!mounted) return;

    switch (availability) {
      case ArAvailability.unsupported:
        setState(() => _stage = _Stage.arUnsupported);
        return;
      case ArAvailability.needsInstall:
        final installed = await _ar.requestInstall();
        if (!mounted) return;
        if (!installed) {
          setState(() => _stage = _Stage.needsInstall);
          return;
        }
        break;
      case ArAvailability.ready:
      case ArAvailability.unknown:
        break;
    }

    setState(() => _stage = _Stage.ready);
    _startGuidance();
  }

  Future<void> _startGuidance() async {
    if (await _location.ensureReady()) {
      final first = await _location.current();
      if (mounted && first != null) {
        setState(() {
          _position = first;
          _target ??= _nearestTo(first);
        });
        _maybeSendPose();
        _maybeFetchRoute();
      }
      _positionSub = _location.stream().listen((p) {
        if (!mounted) return;
        setState(() {
          _position = p;
          _target ??= _nearestTo(p);
        });
        _maybeSendPose();
        _maybeFetchRoute();
      });
    }

    if (_compass.isSupported) {
      _headingSub = _compass.stream().listen((h) {
        if (!mounted) return;
        setState(() => _heading = h);
        _maybeSendPose();
      });
    }
  }

  void _onArController(ArViewController controller) {
    _arController = controller;
    final route = _route;
    final target = _target;
    if (route != null && target != null) {
      controller.setRoute(route.points, target.location);
    }
    _maybeSendPose();
  }

  void _maybeSendPose() {
    final p = _position;
    final h = _heading;
    if (p == null || h == null) return;
    _arController?.updatePose(
      lat: p.location.latitude,
      lng: p.location.longitude,
      heading: h,
      accuracy: p.accuracyMeters,
    );
  }

  Future<void> _maybeFetchRoute() async {
    final target = _target;
    final origin = _position?.location;
    if (target == null || origin == null || _routeFetching) return;

    final bool sameTarget = _routeTargetId == target.id;
    final bool nearOrigin = _routeOrigin != null &&
        GeoUtils.distanceMeters(origin, _routeOrigin!) < 25;
    if (_route != null && sameTarget && nearOrigin) return;

    _routeFetching = true;
    final route = await _routing.route(origin, target.location);
    _routeFetching = false;
    if (!mounted || _target?.id != target.id) return;
    setState(() {
      _route = route;
      _routeOrigin = origin;
      _routeTargetId = target.id;
    });
    _arController?.setRoute(route.points, target.location);
  }

  CampusBuilding _nearestTo(UserPosition p) {
    final list = List<CampusBuilding>.from(CampusData.buildings);
    list.sort((a, b) => GeoUtils.distanceMeters(p.location, a.location)
        .compareTo(GeoUtils.distanceMeters(p.location, b.location)));
    return list.first;
  }

  Future<void> _changeTarget() async {
    final chosen = await BuildingListSheet.show(
      context,
      userLocation: _position?.location,
      selectedId: _target?.id,
      title: 'Navigate to…',
    );
    if (chosen != null && mounted) {
      setState(() {
        _target = chosen;
        _route = null;
        _routeTargetId = null;
      });
      _arController?.clearRoute();
      _maybeFetchRoute();
    }
  }

  void _openMapInstead() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_stage) {
        _Stage.checking => _centeredDark(
            const CircularProgressIndicator(color: Colors.white),
            'Preparing AR…',
          ),
        _Stage.cameraDenied => _PermissionState(
            icon: Icons.no_photography_outlined,
            title: 'Camera access needed',
            message:
                'AR navigation uses the camera to overlay directions on the path '
                'ahead. Grant camera access to continue.',
            primaryLabel: 'Grant camera access',
            onPrimary: _init,
            onSecondary: _openMapInstead,
          ),
        _Stage.arUnsupported => _PermissionState(
            icon: Icons.view_in_ar_outlined,
            title: 'AR not available on this device',
            message:
                'This device does not support Google Play Services for AR. You '
                'can still use the campus map to find your way.',
            primaryLabel: 'Open Map instead',
            onPrimary: _openMapInstead,
          ),
        _Stage.needsInstall => _PermissionState(
            icon: Icons.system_update_outlined,
            title: 'AR service required',
            message:
                'Google Play Services for AR needs to be installed or updated '
                'to use AR navigation.',
            primaryLabel: 'Install / update',
            onPrimary: _init,
            onSecondary: _openMapInstead,
          ),
        _Stage.ready => _buildReady(),
      },
    );
  }

  Widget _buildReady() {
    final target = _target;
    final bool hasGuidance =
        _position != null && _heading != null && target != null;

    double? distance;
    double? bearing;
    double? relative;
    if (_position != null && target != null) {
      distance = GeoUtils.distanceMeters(_position!.location, target.location);
      bearing = GeoUtils.bearingDegrees(_position!.location, target.location);
      if (_heading != null) {
        relative = GeoUtils.relativeAngle(_heading!, bearing);
      }
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ArCameraView(
          onStatus: (s) {
            if (mounted) setState(() => _arStatus = s);
          },
          onControllerCreated: _onArController,
        ),
        if (target == null)
          _centeredDark(
            const CircularProgressIndicator(color: Colors.white),
            'Finding the nearest building…',
          )
        else
          ArHud(
            building: target,
            status: _arStatus,
            route: _route,
            distanceMeters: distance,
            relativeDegrees: relative,
            bearingDegrees: bearing,
            hasGuidance: hasGuidance,
            onChangeTarget: _changeTarget,
            onBack: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }

  Widget _centeredDark(Widget indicator, String label) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(height: 18),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 15)),
        ],
      ),
    );
  }
}

class _PermissionState extends StatelessWidget {
  const _PermissionState({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            const Spacer(),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.brandLight, size: 46),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
            ),
            if (onSecondary != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: onSecondary,
                  child: const Text(
                    'Back to map',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
