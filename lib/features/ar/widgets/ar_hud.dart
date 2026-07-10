import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/geo_utils.dart';
import '../../../data/models/campus_building.dart';
import '../../../data/models/walking_route.dart';
import '../ar_view.dart';

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
    final bool arrived = distanceMeters != null && distanceMeters! <= 12;
    final bool showTurn = hasGuidance && !arrived;

    return SafeArea(
      child: Column(
        children: [
          _topBar(context),
          const Spacer(),
          // The camera centre stays clear for the in-world AR guidance (the 3D
          // pin, chevrons and card). Only acquiring / arrived states use it.
          if (arrived)
            _ArrivedBadge(name: building.name)
          else if (!hasGuidance)
            _acquiringGuidance(context),
          const Spacer(),
          // Turn guidance lives at the bottom-centre as a compact floating pill,
          // so it never blocks the view of the path ahead.
          if (showTurn) _TurnPill(rel: rel, relRadians: relRadians),
          if (showTurn) const SizedBox(height: 10),
          _infoCard(context),
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

  Widget _infoCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
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
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(building.category.icon,
                    color: AppColors.brandLight, size: 18),
              ),
              const SizedBox(width: 10),
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
              if (bearingDegrees != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.explore_outlined,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 5),
                      Text(
                        GeoUtils.compassLabel(bearingDegrees!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _primaryDistance,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 14),
              if (_stepsText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Row(
                    children: [
                      const Icon(Icons.directions_walk,
                          color: Colors.white70, size: 15),
                      const SizedBox(width: 5),
                      Text(
                        route != null
                            ? '${_stepsText!} · ${route!.etaLabel}'
                            : _stepsText!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
            ],
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

/// A compact, floating turn indicator shown at the bottom-centre: a rotating
/// arrow plus the turn instruction. Keeps the camera centre clear so the user
/// can see the path and the in-world 3D guidance.
class _TurnPill extends StatelessWidget {
  const _TurnPill({required this.rel, required this.relRadians});

  final double rel;
  final double relRadians;

  @override
  Widget build(BuildContext context) {
    final bool onCourse = rel.abs() <= 15;
    final Color color = onCourse ? AppColors.brandLight : AppColors.accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
              border:
                  Border.all(color: color.withValues(alpha: 0.65), width: 2),
            ),
            child: Center(
              child: AnimatedRotation(
                turns: relRadians / (2 * math.pi),
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  onCourse
                      ? Icons.arrow_upward_rounded
                      : Icons.navigation_rounded,
                  color: color,
                  size: 26,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              GeoUtils.turnInstruction(rel),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
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
