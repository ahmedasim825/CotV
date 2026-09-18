import 'dart:ui' as ui;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/providers/ambient_providers.dart';
import 'src/providers/chat_session_providers.dart';
import 'src/services/supabase_config.dart';
import 'src/storage/local_storage.dart';
import 'src/ui/app_shell.dart';
import 'src/ui/components/liquid_glass.dart';
import 'src/ui/security_gate.dart';
import 'src/ui/theme/app_theme.dart';
import 'src/ui/widgets/orb_field_background.dart';

/// Set by `tool/ios_preview.dart` so a dev run keeps its own Hive directory
/// and can sit alongside the installed build instead of failing to open it.
String? debugStorageSubdirectory;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeLocalStorage(subdirectory: debugStorageSubdirectory);

  // Opened once, here, and handed to the scope as an override. A provider
  // that opened it lazily could open a second connection to the same file,
  // and two connections in WAL mode see different snapshots.
  final database = await bootstrapAppDatabase();

  // Compiled once, here, for the same reason the database is: the program is
  // a process-global, and `FragmentProgram.fromAsset` is a Future that the
  // first frame cannot wait on. Null on any engine that cannot run it, which
  // includes every widget test — the control layer then draws its blur and
  // nothing downstream has to know why.
  final glassProgram = await loadLiquidGlassProgram();

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
      child: PrayerLockoutApp(glassProgram: glassProgram),
    ),
  );
}

class PrayerLockoutApp extends ConsumerWidget {
  const PrayerLockoutApp({super.key, this.glassProgram});

  /// The compiled refraction shader, or null on an engine without one.
  final ui.FragmentProgram? glassProgram;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The provider is the deliberate off switch; a null program is the
    // involuntary one. Both arrive at the same place.
    final refract = ref.watch(liquidGlassRefractionProvider);

    return MaterialApp(
      title: 'Milo',
      debugShowCheckedModeBanner: false,
      // What `autoHideOnModal` on every CN widget needs in order to know a
      // sheet is up. Without it the package cannot tell which route is on top,
      // and falls back to destroying every native control on the page under
      // any modal — including the tab bar, while the task sheet's own switches
      // are open above it.
      navigatorObservers: [CNTabBarRouteObserver()],
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
          // Beside the ground rather than inside it: the scope is inherited
          // data, so it costs nothing to sit above the Navigator, and every
          // route then reaches the same compiled program.
          child: LiquidGlassScope(
            program: refract ? glassProgram : null,
            child: OrbFieldBackground(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
      home: const SecurityGate(child: AppShell()),
    );
  }
}
