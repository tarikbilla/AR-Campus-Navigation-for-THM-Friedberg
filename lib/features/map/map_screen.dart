import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/geo_utils.dart';
import '../../data/campus_data.dart';
import '../../data/models/campus_building.dart';
import '../../data/models/walking_route.dart';
import '../../services/location_service.dart';
import '../../services/permission_service.dart';
import '../../services/routing_service.dart';
import '../../widgets/building_list_sheet.dart';
import '../ar/ar_navigation_screen.dart';
import 'widgets/map_markers.dart';
import 'widgets/route_overlay.dart';

/// Map mode: an interactive OpenStreetMap of the THM Friedberg campus showing
/// the user's live position, every building as a tappable marker, and a
/// road-following walking route to the selected building.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.focusBuildingId});

  /// If provided, the map opens centred on this building with it selected.
  final String? focusBuildingId;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final LocationService _location = LocationService();
  final PermissionService _permissions = const PermissionService();
  final RoutingService _routing = RoutingService();

  StreamSubscription<UserPosition>? _positionSub;
  UserPosition? _userPosition;
  CampusBuilding? _selected;
  WalkingRoute? _route;
  bool _routeLoading = false;
  bool _locationDenied = false;

  AnimationController? _moveCtrl;

  @override
  void initState() {
    super.initState();
    _startLocation();
    final focus = CampusData.byId(widget.focusBuildingId);
    if (focus != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _selectBuilding(focus));
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _location.dispose();
    _moveCtrl?.dispose();
    super.dispose();
  }

  /// Smoothly animates the map camera to [dest]/[zoom] via the controller so the
  /// widget tree is never rebuilt for the movement. Yields to the user if they
  /// start a gesture (see [_cancelMove]).
  void _animatedMove(LatLng dest, double zoom) {
    final MapCamera camera;
    try {
      camera = _mapController.camera;
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(dest, zoom);
        } catch (_) {}
      });
      return;
    }

    _moveCtrl?.dispose();
    final latTween = Tween<double>(
        begin: camera.center.latitude, end: dest.latitude);
    final lngTween = Tween<double>(
        begin: camera.center.longitude, end: dest.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: zoom);

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _moveCtrl = controller;
    final curved = CurvedAnimation(
        parent: controller, curve: Curves.easeInOutCubic);
    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(curved), lngTween.evaluate(curved)),
        zoomTween.evaluate(curved),
      );
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        if (identical(_moveCtrl, controller)) _moveCtrl = null;
      }
    });
    controller.forward();
  }

  void _cancelMove() {
    _moveCtrl?.stop();
    _moveCtrl?.dispose();
    _moveCtrl = null;
  }

  Future<void> _startLocation() async {
    final ready = await _location.ensureReady();
    if (!ready) {
      if (mounted) setState(() => _locationDenied = true);
      return;
    }
    if (mounted) setState(() => _locationDenied = false);

    final first = await _location.current();
    if (mounted && first != null) {
      setState(() => _userPosition = first);
      if (_selected == null) _mapController.move(first.location, 17.5);
    }

    _positionSub = _location.stream().listen((pos) {
      if (mounted) setState(() => _userPosition = pos);
    });
  }

  void _recenter() {
    HapticFeedback.selectionClick();
    final pos = _userPosition;
    if (pos != null) {
      _animatedMove(pos.location, 18);
    } else {
      _animatedMove(AppInfo.campusCenter, AppInfo.defaultMapZoom);
      if (_locationDenied) _promptEnableLocation();
    }
  }

  Future<void> _promptEnableLocation() async {
    final granted = await _permissions.requestLocation();
    if (granted) {
      _startLocation();
      return;
    }
    final permanentlyDenied = await _permissions.isLocationPermanentlyDenied();
    if (!mounted || !permanentlyDenied) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Enable location to see your position on the map.'),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: _permissions.openSettings,
        ),
      ),
    );
  }

  Future<void> _selectBuilding(CampusBuilding b) async {
    HapticFeedback.selectionClick();
    setState(() {
      _selected = b;
      _route = null;
      _routeLoading = true;
    });
    _animatedMove(b.location, 18);
    await _loadRoute(b);
  }

  Future<void> _loadRoute(CampusBuilding b) async {
    final user = _userPosition?.location;
    if (user == null) {
      if (mounted) setState(() => _routeLoading = false);
      return;
    }
    final route = await _routing.route(user, b.location);
    if (!mounted || _selected?.id != b.id) return;
    setState(() {
      _route = route;
      _routeLoading = false;
    });
    _fitRoute(route);
  }

  void _fitRoute(WalkingRoute route) {
    if (route.points.length < 2) return;
    // Cancel any in-flight select animation so it doesn't fight the fit.
    _cancelMove();
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(route.points),
          padding: const EdgeInsets.fromLTRB(50, 120, 50, 230),
        ),
      );
    } catch (_) {
      // Map not ready; ignore.
    }
  }

  void _clearSelection() {
    setState(() {
      _selected = null;
      _route = null;
      _routeLoading = false;
    });
  }

  Future<void> _openSearch() async {
    final chosen = await BuildingListSheet.show(
      context,
      userLocation: _userPosition?.location,
      selectedId: _selected?.id,
    );
    if (chosen != null) _selectBuilding(chosen);
  }

  void _openArForSelected() {
    final b = _selected;
    if (b == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArNavigationScreen(targetBuildingId: b.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Map'),
        actions: [
          IconButton(
            tooltip: 'Search buildings',
            onPressed: _openSearch,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildMap(),
          if (_locationDenied) _buildLocationBanner(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _selected == null
                ? const SizedBox.shrink()
                : _RouteCard(
                    building: _selected!,
                    route: _route,
                    loading: _routeLoading,
                    hasUser: _userPosition != null,
                    onClose: _clearSelection,
                    onNavigateAr: _openArForSelected,
                  ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: _selected != null ? 172 : 0),
        child: FloatingActionButton(
          onPressed: _recenter,
          tooltip: 'Recenter on me',
          child: Icon(_userPosition != null
              ? Icons.my_location
              : Icons.location_searching),
        ),
      ),
    );
  }

  Widget _buildMap() {
    // The map is rebuilt only on genuine state changes (route set/cleared,
    // position, selection) — never per animation frame. Route/marker animation
    // lives inside the marker widgets themselves, and camera movement goes
    // through the controller, so gestures (pinch-zoom / pan) stay smooth.
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: AppInfo.campusCenter,
        initialZoom: AppInfo.defaultMapZoom,
        minZoom: 3,
        maxZoom: 19,
        // A user gesture cancels any in-flight programmatic camera animation.
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture) _cancelMove();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'net.godevs.thmcampusnav',
          maxZoom: 19,
        ),
        if (_route != null)
          ...buildRouteLayers(
            route: _route!,
            scheme: Theme.of(context).colorScheme,
          ),
        if (_userPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: _userPosition!.location,
                width: 28,
                height: 28,
                child: const UserLocationDot(),
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final b in CampusData.buildings)
              Marker(
                point: b.location,
                width: 96,
                height: 54,
                alignment: Alignment.bottomCenter,
                child: BuildingPin(
                  building: b,
                  selected: _selected?.id == b.id,
                  onTap: () => _selectBuilding(b),
                ),
              ),
          ],
        ),
        const RichAttributionWidget(
          attributions: [
            TextSourceAttribution(AppInfo.osmAttribution),
          ],
        ),
      ],
    );
  }

  Widget _buildLocationBanner() {
    final theme = Theme.of(context);
    return Positioned(
      left: 16,
      right: 16,
      top: 12,
      child: Material(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.location_off_outlined,
                  color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Location is off. Showing campus overview.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: _promptEnableLocation,
                child: const Text('Enable'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent bottom navigation card for the selected building.
class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.building,
    required this.route,
    required this.loading,
    required this.hasUser,
    required this.onClose,
    required this.onNavigateAr,
  });

  final CampusBuilding building;
  final WalkingRoute? route;
  final bool loading;
  final bool hasUser;
  final VoidCallback onClose;
  final VoidCallback onNavigateAr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(building.category.icon,
                      color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(building.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium),
                      Text(building.category.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear route',
                ),
              ],
            ),
            const SizedBox(height: 10),
            _stats(theme),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onNavigateAr,
                icon: const Icon(Icons.view_in_ar_outlined),
                label: const Text('Navigate in AR'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stats(ThemeData theme) {
    final scheme = theme.colorScheme;

    if (!hasUser) {
      return _pill(theme, Icons.location_off_outlined,
          'Enable location to get a walking route');
    }
    if (loading || route == null) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text('Finding the best walking route…',
              style: theme.textTheme.bodyMedium),
        ],
      );
    }

    final r = route!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.directions_walk, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Text('Walking route',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                )),
            if (r.isFallback) ...[
              const SizedBox(width: 6),
              Text('(approx.)',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _chip(theme, Icons.schedule, r.etaLabel),
            const SizedBox(width: 10),
            _chip(theme, Icons.straighten,
                GeoUtils.formatDistance(r.distanceMeters)),
          ],
        ),
      ],
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String label) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              )),
        ],
      ),
    );
  }

  Widget _pill(ThemeData theme, IconData icon, String label) {
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.warning),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}
