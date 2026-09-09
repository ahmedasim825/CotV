import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/providers/chat_session_providers.dart';
import 'src/services/supabase_config.dart';
import 'src/storage/local_storage.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/security_gate.dart';
import 'src/ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeLocalStorage();

  // Opened once, here, and handed to the scope as an override. A provider
  // that opened it lazily could open a second connection to the same file,
  // and two connections in WAL mode see different snapshots.
  final database = await bootstrapAppDatabase();

  // Sync is optional: a build with no Supabase defines skips this entirely
  // and the app runs local-only, exactly as it did before sync existed.
  // Initialising with placeholder credentials would throw here and take
  // the whole app down over a feature the user may not be using.
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: const PrayerLockoutApp(),
    ),
  );
}

class PrayerLockoutApp extends ConsumerWidget {
  const PrayerLockoutApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Milo',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      themeAnimationDuration: WidgetsBinding
              .instance.platformDispatcher.accessibilityFeatures.disableAnimations
          ? Duration.zero
          : AppMotion.themeSwitch,
      themeAnimationCurve: AppMotion.spring,
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // kPalette is dark, so the status bar gets light glyphs.
          value: kPalette.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SecurityGate(child: AppShell()),
    );
  }
}
