import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../data/models/campus_building.dart';
import '../../../data/models/walking_route.dart';
import '../ar_view.dart';
import 'direction_arrow.dart';

/// Glanceable heads-up display drawn over the live ARCore camera view. Shows
/// the directional arrow, distance and turn guidance toward the target
/// building, plus the AR tracking status.
class ArHud extends StatelessWidget {
  const ArHud({
    super.key,
    required this.building,
    required this.status,
    required this.route,
    required this.remainingMeters,
    required this.distanceMeters,
    required this.relativeDegrees,
    required this.bearingDegrees,
    required this.hasGuidance,
    required this.onChangeTarget,
    required this.onBack,
  });

  final CampusBuilding building;
  final ArStatus status;
  final WalkingRoute? route;

  /// Walking distance still to go (route-aware); drives the big number + steps.
  final double? remainingMeters;
  final double? distanceMeters;
  final double? relativeDegrees;
  final double? bearingDegrees;
  final bool hasGuidance;
  final VoidCallback onChangeTarget;
  final VoidCallback onBack;

  double? get _shownMeters =>
      remainingMeters ?? route?.distanceMeters ?? distanceMeters;

  /// Remaining walking distance for the big number.
  String get _primaryDistance {
    final double? meters = _shownMeters;
    return meters == null ? '—' : GeoUtils.formatDistance(meters);
  }

  /// Estimated remaining steps, e.g. "170 steps".
  String? get _stepsText {
    final double? meters = _shownMeters;
    if (meters == null) return null;
    return '${GeoUtils.stepsForMeters(meters)} steps';
  }

  @override
  Widget build(BuildContext context) {
    final double rel = relativeDegrees ?? 0;
    final double relRadians = rel * math.pi / 180.0;
    final bool arrived =
        distanceMeters != null && distanceMeters! <= 12;

    return SafeArea(
      child: Column(
        children: [
          _topBar(context),
          const Spacer(),
          if (hasGuidance)
            _centerGuidance(context, rel, relRadians, arrived)
          else
            _acquiringGuidance(context),
          const Spacer(),
          _bottomCard(context, rel, arrived),
        ],
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _CircleButton(icon: Icons.arrow_back, onTap: onBack),
          const SizedBox(width: 10),
          Expanded(child: _StatusPill(status: status)),
          const SizedBox(width: 10),
          _CircleButton(icon: Icons.tune, onTap: onChangeTarget),
        ],
      ),
    );
  }

  Widget _centerGuidance(
      BuildContext context, double rel, double relRadians, bool arrived) {
    if (arrived) {
      return _ArrivedBadge(name: building.name);
    }
    final Color arrowColor =
        rel.abs() <= 20 ? AppColors.brandLight : AppColors.accent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DirectionArrow(angleRadians: relRadians, color: arrowColor),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.hudScrim,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            GeoUtils.turnInstruction(rel),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _acquiringGuidance(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.hudScrim,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Acquiring GPS & compass…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Hold the phone up and move it in a figure-8 to calibrate.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _bottomCard(BuildContext context, double rel, bool arrived) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(building.category.icon,
                        color: AppColors.brandLight, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        building.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _primaryDistance,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_stepsText != null)
                            Row(
                              children: [
                                const Icon(Icons.directions_walk,
                                    color: Colors.white70, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  route != null
                                      ? '${_stepsText!} · ${route!.etaLabel}'
                                      : _stepsText!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          Text(
                            bearingDegrees == null
                                ? 'to destination'
                                : 'toward ${GeoUtils.compassLabel(bearingDegrees!)}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (hasGuidance && !arrived)
            MiniCompass(
              relativeAngleRadians: rel * math.pi / 180.0,
              color: AppColors.brandLight,
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final ArStatus status;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String label;
    late final Color color;

    if (!status.isTracking) {
      icon = Icons.motion_photos_on_outlined;
      label = 'Move phone to start AR';
      color = AppColors.warning;
    } else if (!status.hasPlanes) {
      icon = Icons.grid_on_outlined;
      label = 'Scanning the ground…';
      color = AppColors.accent;
    } else {
      icon = Icons.check_circle_outline;
      label = 'AR ready · ${status.planeCount} surface'
          '${status.planeCount == 1 ? '' : 's'}';
      color = AppColors.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.hudScrim,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.hudScrim,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _ArrivedBadge extends StatelessWidget {
  const _ArrivedBadge({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 36),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.flag_circle_outlined,
              color: Colors.white, size: 56),
          const SizedBox(height: 12),
          const Text(
            "You've arrived",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
