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
import 'src/ui/widgets/orb_field_background.dart';

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
      // No `background:` override: the ground is one fixed colour now, so it
      // comes straight off `kPalette.background`. The parameter stays on
      // [buildAppTheme] as a general escape hatch — see its doc.
      theme: buildAppTheme(),
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          // The ground is dark, so the status bar gets light glyphs.
          value: kPalette.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          // Inside the region and above the [Navigator]: one ground for the
          // whole app, continuous across route pushes, which is why no screen
          // paints its own any more.
          child: OrbFieldBackground(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const SecurityGate(child: AppShell()),
    );
  }
}
