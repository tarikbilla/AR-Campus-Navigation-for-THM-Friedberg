import 'package:flutter/material.dart';

import 'core/constants/app_info.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';

/// Root application widget. No authentication, no onboarding wall — the app
/// opens on a branded splash that fades straight into the home screen.
class ThmCampusApp extends StatelessWidget {
  const ThmCampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppInfo.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const SplashScreen(),
    );
  }
}
