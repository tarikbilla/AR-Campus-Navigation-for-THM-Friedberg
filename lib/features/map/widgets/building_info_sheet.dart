import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/geo_utils.dart';
import '../../../data/models/campus_building.dart';

/// Bottom-sheet content shown when a building is selected on the map. Displays
/// name, category, live distance/bearing and an action to open AR navigation.
class BuildingInfoSheet extends StatelessWidget {
  const BuildingInfoSheet({
    super.key,
    required this.building,
    required this.userLocation,
    required this.onNavigateAr,
  });

  final CampusBuilding building;
  final LatLng? userLocation;
  final VoidCallback onNavigateAr;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final double? distance = userLocation == null
        ? null
        : GeoUtils.distanceMeters(userLocation!, building.location);
    final double? bearing = userLocation == null
        ? null
        : GeoUtils.bearingDegrees(userLocation!, building.location);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(building.category.icon,
                      color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(building.name, style: theme.textTheme.titleLarge),
                      Text(
                        '${building.code} · ${building.category.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (building.description != null) ...[
              const SizedBox(height: 14),
              Text(
                building.description!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                _Stat(
                  icon: Icons.near_me_outlined,
                  label: 'Distance',
                  value: distance == null
                      ? '—'
                      : GeoUtils.formatDistance(distance),
                ),
                const SizedBox(width: 12),
                _Stat(
                  icon: Icons.explore_outlined,
                  label: 'Direction',
                  value: bearing == null
                      ? '—'
                      : GeoUtils.compassLabel(bearing),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onNavigateAr,
              icon: const Icon(Icons.view_in_ar_outlined),
              label: const Text('Navigate in AR'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    )),
                Text(value,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
