import 'package:flutter/material.dart';

/// Central colour palette for the app.
///
/// The primary is inspired by the THM (Technische Hochschule Mittelhessen)
/// green identity, paired with a clean neutral surface set and a set of
/// utility colours used by the AR HUD and map overlays.
class AppColors {
  AppColors._();

  /// THM-inspired brand green.
  static const Color brand = Color(0xFF009640);
  static const Color brandDark = Color(0xFF00702F);
  static const Color brandLight = Color(0xFF4CC47C);

  /// Secondary accent used for AR/interactive highlights.
  static const Color accent = Color(0xFF0F9BF2);
  static const Color accentDark = Color(0xFF0A6FB0);

  /// Semantic colours.
  static const Color success = Color(0xFF1FA463);
  static const Color warning = Color(0xFFF3A712);
  static const Color danger = Color(0xFFE5484D);

  /// Light theme neutrals.
  static const Color lightBackground = Color(0xFFF6F8F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFEDF2EF);

  /// Dark theme neutrals.
  static const Color darkBackground = Color(0xFF0E1512);
  static const Color darkSurface = Color(0xFF16201C);
  static const Color darkSurfaceAlt = Color(0xFF1F2C26);

  /// Brand gradient used on hero surfaces and primary buttons.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand, brandDark],
  );

  /// Cool AR gradient used on the AR mode card / HUD accents.
  static const LinearGradient arGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentDark],
  );

  /// Translucent scrim used behind HUD text on the camera view.
  static const Color hudScrim = Color(0xB3000000);
}
