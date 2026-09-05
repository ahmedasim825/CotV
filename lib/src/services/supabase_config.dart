/// Where the sync backend lives, and the key the app talks to it with.
///
/// Both come from the build, with placeholders as the default — the same
/// split MiloCredentials and FoodApiService use. The publishable key is
/// not a secret (it is designed to ship inside clients and every table it
/// can reach is behind row-level security), but keeping it out of the
/// repository means a fork of this code cannot write to this project.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'YOUR_SUPABASE_URL',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'YOUR_SUPABASE_PUBLISHABLE_KEY',
  );

  /// False while the placeholders are in place.
  ///
  /// Everything sync-related is gated on this. A build without the defines
  /// runs exactly as it did before sync existed: the log and recipes stay
  /// in memory and the account section says so, rather than the app
  /// failing at startup over a backend it was never given.
  static bool get isConfigured =>
      !url.startsWith('YOUR_') && !publishableKey.startsWith('YOUR_');

  static const String notConfiguredMessage =
      'Sync is not set up in this build. Rebuild with '
      '--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_PUBLISHABLE_KEY=…';
}
