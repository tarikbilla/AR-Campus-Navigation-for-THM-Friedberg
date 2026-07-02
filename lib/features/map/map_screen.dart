import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/constants/app_info.dart';
import '../../data/campus_data.dart';
import '../../data/models/campus_building.dart';
import '../../services/location_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/building_list_sheet.dart';
import '../ar/ar_navigation_screen.dart';
import 'widgets/building_info_sheet.dart';
import 'widgets/map_markers.dart';

/// Map mode: an interactive OpenStreetMap of the THM Friedberg campus showing
/// the user's live position and every main building as a tappable marker.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.focusBuildingId});

  /// If provided, the map opens centred on this building with it selected.
  final String? focusBuildingId;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final LocationService _location = LocationService();
  final PermissionService _permissions = const PermissionService();

  StreamSubscription<UserPosition>? _positionSub;
  UserPosition? _userPosition;
  CampusBuilding? _selected;
  bool _locationDenied = false;

  @override
  void initState() {
    super.initState();
    _selected = CampusData.byId(widget.focusBuildingId);
    _startLocation();
    if (_selected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.move(_selected!.location, 18);
        _showBuildingSheet(_selected!);
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _location.dispose();
    super.dispose();
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
    final pos = _userPosition;
    if (pos != null) {
      _mapController.move(pos.location, 18);
    } else {
      _mapController.move(AppInfo.campusCenter, AppInfo.defaultMapZoom);
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

  void _selectBuilding(CampusBuilding b) {
    setState(() => _selected = b);
    _mapController.move(b.location, 18);
    _showBuildingSheet(b);
  }

  void _showBuildingSheet(CampusBuilding b) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => BuildingInfoSheet(
        building: b,
        userLocation: _userPosition?.location,
        onNavigateAr: () {
          Navigator.of(context).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArNavigationScreen(targetBuildingId: b.id),
            ),
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _selected = null);
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _recenter,
        tooltip: 'Recenter on me',
        child: Icon(_userPosition != null
            ? Icons.my_location
            : Icons.location_searching),
      ),
    );
  }

  Widget _buildMap() {
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: AppInfo.campusCenter,
        initialZoom: AppInfo.defaultMapZoom,
        minZoom: 3,
        maxZoom: 19,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'net.godevs.thmcampusnav',
          maxZoom: 19,
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
