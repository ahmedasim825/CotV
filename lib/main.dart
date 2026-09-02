import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/providers/theme_providers.dart';
import 'src/storage/local_storage.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/security_gate.dart';
import 'src/ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeLocalStorage();
  runApp(const ProviderScope(child: PrayerLockoutApp()));
}

class PrayerLockoutApp extends ConsumerWidget {
  const PrayerLockoutApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(themeVariantProvider);

    return MaterialApp(
      title: 'Prayer Lockout',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(variant),
      // Switching themes cross-fades every color in the tree rather than
      // cutting, since the palette travels as a lerp-able ThemeExtension.
      themeAnimationDuration: AppMotion.themeSwitch,
      themeAnimationCurve: AppMotion.spring,
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // The one light theme needs dark status-bar glyphs; every other
          // variant needs light ones.
          value: variant.palette.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SecurityGate(child: AppShell()),
    );
  }
}
