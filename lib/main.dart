import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/ui/home_screen.dart';
import 'src/ui/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: PrayerLockoutApp()));
}

class PrayerLockoutApp extends StatelessWidget {
  const PrayerLockoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prayer Lockout',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
