import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/storage/local_storage.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/security_gate.dart';
import 'src/ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeLocalStorage();
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
      home: const SecurityGate(child: HomeScreen()),
    );
  }
}
