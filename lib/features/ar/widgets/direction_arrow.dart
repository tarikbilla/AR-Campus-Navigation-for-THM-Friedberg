import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A large, glowing directional arrow that rotates to point toward the target
/// building. An angle of 0 points straight up (target dead ahead); positive
/// angles rotate clockwise (target to the right).
class DirectionArrow extends StatelessWidget {
  const DirectionArrow({
    super.key,
    required this.angleRadians,
    required this.color,
    this.size = 180,
  });

  final double angleRadians;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: angleRadians / (2 * math.pi),
      duration: const Duration(milliseconds: 150),
      child: CustomPaint(
        size: Size(size, size),
        painter: _ArrowPainter(color),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Offset center = Offset(w / 2, h / 2);

    // Arrow geometry (pointing up), centred.
    final Path arrow = Path();
    final double halfW = w * 0.30;
    final double headH = h * 0.42;
    final double shaftW = w * 0.14;

    arrow.moveTo(center.dx, h * 0.06); // tip
    arrow.lineTo(center.dx + halfW, h * 0.06 + headH); // right head
    arrow.lineTo(center.dx + shaftW, h * 0.06 + headH);
    arrow.lineTo(center.dx + shaftW, h * 0.92); // right shaft bottom
    arrow.lineTo(center.dx - shaftW, h * 0.92); // left shaft bottom
    arrow.lineTo(center.dx - shaftW, h * 0.06 + headH);
    arrow.lineTo(center.dx - halfW, h * 0.06 + headH); // left head
    arrow.close();

    // Soft outer glow.
    final Paint glow = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawPath(arrow, glow);

    // Gradient fill.
    final Rect rect = Rect.fromLTWH(0, 0, w, h);
    final Paint fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.lerp(color, Colors.white, 0.25)!,
          color,
        ],
      ).createShader(rect);
    canvas.drawPath(arrow, fill);

    // Thin white outline for contrast against the camera feed.
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(arrow, stroke);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// A compact compass ring showing the target bearing relative to the device
/// heading, used as a secondary cue in the HUD.
class MiniCompass extends StatelessWidget {
  const MiniCompass({
    super.key,
    required this.relativeAngleRadians,
    required this.color,
    this.size = 54,
  });

  final double relativeAngleRadians;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MiniCompassPainter(relativeAngleRadians, color),
      ),
    );
  }
}

class _MiniCompassPainter extends CustomPainter {
  _MiniCompassPainter(this.angle, this.color);
  final double angle;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double r = size.width / 2 - 3;

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.7);
    canvas.drawCircle(c, r, ring);

    // Direction dot on the ring.
    final Offset dot = Offset(
      c.dx + r * math.sin(angle),
      c.dy - r * math.cos(angle),
    );
    canvas.drawCircle(dot, 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MiniCompassPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.color != color;
}
