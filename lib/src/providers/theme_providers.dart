import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/theme/app_theme.dart';
import 'user_settings_providers.dart';

/// The theme the app is currently painted in.
///
/// Reads from the persisted [UserSettings.themeId], falling back to
/// [AppThemeVariant.fallback] both before anything has been chosen and if a
/// stored id no longer matches a known variant.
///
/// [userSettingsControllerProvider] is a stream and so is momentarily
/// loading on a cold start; the repository's synchronous `get()` covers
/// that first frame, so the app never flashes the default theme before
/// settling on the chosen one.
final themeVariantProvider = Provider<AppThemeVariant>((ref) {
  final settingsAsync = ref.watch(userSettingsControllerProvider);
  final settings =
      settingsAsync.value ?? ref.watch(userSettingsRepositoryProvider).get();
  return AppThemeVariant.fromId(settings.themeId);
});
