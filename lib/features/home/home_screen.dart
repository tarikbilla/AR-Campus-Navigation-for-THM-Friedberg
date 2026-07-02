import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/geo_utils.dart';
import '../../data/campus_data.dart';
import '../../data/models/campus_building.dart';
import '../../services/ar_availability_service.dart';
import '../../services/location_service.dart';
import '../../services/permission_service.dart';
import '../../widgets/building_tile.dart';
import '../ar/ar_navigation_screen.dart';
import '../map/map_screen.dart';
import 'widgets/mode_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocationService _location = LocationService();
  final PermissionService _permissions = const PermissionService();
  final ArAvailabilityService _ar = const ArAvailabilityService();

  LatLng? _userLocation;
  ArAvailability _arAvailability = ArAvailability.unknown;
  bool _loadingLocation = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final availability = await _ar.check();
    if (mounted) setState(() => _arAvailability = availability);

    if (await _permissions.hasLocation()) {
      await _refreshLocation();
    }
  }

  Future<void> _refreshLocation() async {
    setState(() => _loadingLocation = true);
    final pos = await _location.current();
    if (!mounted) return;
    setState(() {
      _userLocation = pos?.location;
      _loadingLocation = false;
    });
  }

  Future<void> _openMap({CampusBuilding? focus}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MapScreen(focusBuildingId: focus?.id),
      ),
    );
    // Refresh nearby list on return in case the user moved / granted location.
    if (await _permissions.hasLocation()) {
      await _refreshLocation();
    }
  }

  Future<void> _openAr({CampusBuilding? target}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArNavigationScreen(targetBuildingId: target?.id),
      ),
    );
  }

  List<CampusBuilding> get _nearby {
    final user = _userLocation;
    final list = List<CampusBuilding>.from(CampusData.buildings);
    if (user != null) {
      list.sort((a, b) => GeoUtils.distanceMeters(user, a.location)
          .compareTo(GeoUtils.distanceMeters(user, b.location)));
    }
    return list.take(4).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = _userLocation;

    return Scaffold(
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refreshLocation,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Header(loading: _loadingLocation)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                sliver: SliverList.list(children: [
                  Text('Navigation modes',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ModeCard(
                    title: 'Map Mode',
                    subtitle:
                        'See your position and every campus building on an interactive map.',
                    icon: Icons.map_outlined,
                    gradient: AppColors.brandGradient,
                    onTap: _openMap,
                  ),
                  const SizedBox(height: 14),
                  ModeCard(
                    title: 'AR Mode',
                    subtitle: _arSubtitle,
                    icon: Icons.view_in_ar_outlined,
                    gradient: AppColors.arGradient,
                    badge: 'ARCore',
                    onTap: _openAr,
                  ),
                ]),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        user != null ? 'Nearby buildings' : 'Campus buildings',
                        style: theme.textTheme.titleMedium,
                      ),
                      if (user == null && !_loadingLocation)
                        TextButton.icon(
                          onPressed: _enableLocation,
                          icon: const Icon(Icons.my_location, size: 18),
                          label: const Text('Use my location'),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                sliver: SliverList.separated(
                  itemCount: _nearby.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (context, i) {
                    final b = _nearby[i];
                    return BuildingTile(
                      building: b,
                      distanceMeters: user == null
                          ? null
                          : GeoUtils.distanceMeters(user, b.location),
                      onTap: () => _showBuildingActions(b),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: _Footer()),
            ],
          ),
        ),
      ),
    );
  }

  String get _arSubtitle {
    switch (_arAvailability) {
      case ArAvailability.unsupported:
        return 'AR is not supported on this device — Map mode still works.';
      case ArAvailability.needsInstall:
        return 'Point your camera at the path and follow the arrow to a building.';
      case ArAvailability.ready:
      case ArAvailability.unknown:
        return 'Follow a live arrow through your camera straight to any building.';
    }
  }

  Future<void> _enableLocation() async {
    final granted = await _permissions.requestLocation();
    if (granted) {
      await _refreshLocation();
    } else if (mounted && await _permissions.isLocationPermanentlyDenied()) {
      _showSettingsSnack('Location permission is disabled.');
    }
  }

  void _showSettingsSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Settings',
          onPressed: _permissions.openSettings,
        ),
      ),
    );
  }

  void _showBuildingActions(CampusBuilding b) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Text(b.name, style: theme.textTheme.titleLarge),
              ),
              if (b.description != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Text(b.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )),
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openMap(focus: b);
                        },
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('On map'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _openAr(target: b);
                        },
                        icon: const Icon(Icons.view_in_ar_outlined),
                        label: const Text('In AR'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(20, topInset + 20, 20, 28),
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.explore_outlined,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppInfo.appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Find your way across\nthe THM Friedberg campus',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.place_outlined,
                  color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  AppInfo.campusName,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
      child: Column(
        children: [
          Divider(color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          Text(
            AppInfo.campusAddress,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No account needed · works offline for guidance',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
