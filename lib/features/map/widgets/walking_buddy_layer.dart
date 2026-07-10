import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
// latlong2 also exports a `Path` type, which would shadow Flutter's Path used
// in the CustomPainter below.
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/geo_utils.dart';

/// A lively, fully-animated walking character that briskly travels the route
/// from origin to destination on a loop — swinging its arms and legs, bobbing as
/// it steps, facing its direction of travel and leaving a fading motion trail.
///
/// It is a direct child of `FlutterMap`, so it reads the live [MapCamera] and
/// projects its moving geographic position to screen every frame — the
/// character stays glued to the path as you pan/zoom, and only this layer
/// repaints (never the whole map), keeping gestures smooth. Everything is drawn
/// in a single [CustomPainter] (no image assets), so it stays crisp at any zoom.
class WalkingBuddyLayer extends StatefulWidget {
  const WalkingBuddyLayer({super.key, required this.route});

  /// Ordered route polyline (origin → destination).
  final List<LatLng> route;

  @override
  State<WalkingBuddyLayer> createState() => _WalkingBuddyLayerState();
}

class _WalkingBuddyLayerState extends State<WalkingBuddyLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<double> _cumulative;
  late double _total;

  @override
  void initState() {
    super.initState();
    _measure();
    _controller = AnimationController(vsync: this, duration: _loopDuration())
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant WalkingBuddyLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.route, widget.route)) {
      _measure();
      _controller.duration = _loopDuration();
      _controller
        ..reset()
        ..repeat();
    }
  }

  void _measure() {
    final pts = widget.route;
    final cum = <double>[];
    double acc = 0;
    for (int i = 0; i < pts.length; i++) {
      if (i > 0) acc += GeoUtils.distanceMeters(pts[i - 1], pts[i]);
      cum.add(acc);
    }
    _cumulative = cum;
    _total = cum.isEmpty ? 0 : cum.last;
  }

  /// One brisk traversal: ~1 s per 30 m, clamped to a snappy 2.5–6.5 s so short
  /// routes still feel energetic and long ones don't drag.
  Duration _loopDuration() {
    final seconds = (_total / 30.0).clamp(2.5, 6.5);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.route.length < 2 || _total <= 1) {
      return const SizedBox.shrink();
    }
    // Establishes a dependency on the camera so we re-project on pan/zoom.
    final camera = MapCamera.of(context);

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final double t = _controller.value;
          final double d = t * _total;

          final Offset here = camera.latLngToScreenOffset(_pointAt(d));
          final Offset ahead =
              camera.latLngToScreenOffset(_pointAt(math.min(d + 2.5, _total)));

          // Fading breadcrumb trail a few metres behind the walker.
          final trail = <Offset>[];
          for (int k = 1; k <= 6; k++) {
            final back = d - k * 2.2;
            if (back <= 0) break;
            trail.add(camera.latLngToScreenOffset(_pointAt(back)));
          }

          // Ease out as it reaches the destination, then it loops.
          final double fade = t > 0.93 ? (1 - t) / 0.07 : 1.0;

          return CustomPaint(
            size: Size.infinite,
            painter: _BuddyPainter(
              position: here,
              ahead: ahead,
              trail: trail,
              // A step every ~0.8 m keeps the legs pumping at walking cadence.
              stepPhase: (d / 0.8) % 1.0,
              opacity: fade.clamp(0.0, 1.0),
            ),
          );
        },
      ),
    );
  }

  LatLng _pointAt(double d) {
    final pts = widget.route;
    if (d <= 0) return pts.first;
    if (d >= _total) return pts.last;
    for (int i = 1; i < pts.length; i++) {
      if (_cumulative[i] >= d) {
        final segLen = _cumulative[i] - _cumulative[i - 1];
        final tt = segLen == 0 ? 0.0 : (d - _cumulative[i - 1]) / segLen;
        return LatLng(
          pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * tt,
          pts[i - 1].longitude +
              (pts[i].longitude - pts[i - 1].longitude) * tt,
        );
      }
    }
    return pts.last;
  }
}

/// Paints the trail, ground shadow, an articulated walking figure, and a heading
/// chevron — all in screen space at the projected [position].
class _BuddyPainter extends CustomPainter {
  _BuddyPainter({
    required this.position,
    required this.ahead,
    required this.trail,
    required this.stepPhase,
    required this.opacity,
  });

  final Offset position;
  final Offset ahead;
  final List<Offset> trail;
  final double stepPhase; // 0..1, one full stride
  final double opacity;

  static const Color _green = AppColors.brand;
  static const Color _greenDark = AppColors.brandDark;
  static const Color _skin = Color(0xFFF3C6A0);

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    // Screen-space travel direction (robust to any map rotation).
    Offset dir = ahead - position;
    if (dir.distance < 0.001) dir = const Offset(0, -1);
    dir = dir / dir.distance;
    final bool faceLeft = dir.dx < 0;

    // ---- Motion trail (accent dots that fade toward the tail) ----
    for (int i = 0; i < trail.length; i++) {
      final f = 1 - i / (trail.length + 1);
      final p = Paint()
        ..color = AppColors.accent.withValues(alpha: 0.30 * f * opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(trail[i], (6.5 * f).clamp(1.5, 6.5), p);
    }

    // Stride phase → swing + vertical bob (feet stay planted, hips lift).
    final double swing = math.sin(stepPhase * math.pi * 2); // -1..1
    final double bob = math.sin(stepPhase * math.pi * 2).abs(); // 0..1

    // ---- Ground shadow (squashes as the body lifts) ----
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.22 * opacity)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(
        center: position + const Offset(0, 2),
        width: 18 - bob * 3,
        height: 5,
      ),
      shadow,
    );

    // ---- Soft glow behind the figure ----
    canvas.drawCircle(
      position + const Offset(0, -18),
      15,
      Paint()..color = _green.withValues(alpha: 0.16 * opacity),
    );

    canvas.save();
    canvas.translate(position.dx, position.dy);
    if (faceLeft) canvas.scale(-1, 1); // mirror so it faces travel direction

    final double bodyDy = -bob * 3; // hips/shoulders lift on mid-stride

    // Joint positions (feet at y = 0).
    final hip = Offset(0, -13 + bodyDy);
    final shoulder = Offset(0, -27 + bodyDy);
    final head = Offset(1.5, -33 + bodyDy);
    final double footSwing = swing * 6.5;
    final double armSwing = -swing * 5.5;

    final white = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.4
      ..strokeCap = StrokeCap.round;
    final limbs = Paint()
      ..color = _green.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    final armsPaint = Paint()
      ..color = _greenDark.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // Legs (white halo first for contrast on a busy map, then colour).
    final leg1 = Offset(footSwing, 0);
    final leg2 = Offset(-footSwing, 0);
    canvas.drawLine(hip, leg1, white);
    canvas.drawLine(hip, leg2, white);
    canvas.drawLine(hip, leg1, limbs);
    canvas.drawLine(hip, leg2, limbs);

    // Torso.
    canvas.drawLine(hip, shoulder, white);
    canvas.drawLine(hip, shoulder, limbs);

    // Arms.
    final hand1 = Offset(armSwing, -18 + bodyDy);
    final hand2 = Offset(-armSwing, -18 + bodyDy);
    canvas.drawLine(shoulder, hand1, white);
    canvas.drawLine(shoulder, hand2, white);
    canvas.drawLine(shoulder, hand1, armsPaint);
    canvas.drawLine(shoulder, hand2, armsPaint);

    // Head.
    canvas.drawCircle(
        head, 6.2, Paint()..color = Colors.white.withValues(alpha: opacity));
    canvas.drawCircle(
        head, 4.6, Paint()..color = _skin.withValues(alpha: opacity));

    canvas.restore();

    // ---- Heading chevron ahead of the walker (true screen direction) ----
    final tip = position + dir * 22 + const Offset(0, -18);
    final perp = Offset(-dir.dy, dir.dx);
    final chevron = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((tip - dir * 7 + perp * 5).dx, (tip - dir * 7 + perp * 5).dy)
      ..lineTo((tip - dir * 7 - perp * 5).dx, (tip - dir * 7 - perp * 5).dy)
      ..close();
    canvas.drawPath(
      chevron,
      Paint()..color = AppColors.accent.withValues(alpha: 0.9 * opacity),
    );
    canvas.drawPath(
      chevron,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BuddyPainter old) =>
      old.position != position ||
      old.stepPhase != stepPhase ||
      old.opacity != opacity;
}
