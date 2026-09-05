import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/nutrition_sync_service.dart';
import '../services/supabase_config.dart';

/// The Supabase client, or null in a build with no backend configured.
///
/// Nullable rather than throwing, because signed-out and not-configured are
/// both states the app runs in normally — sync is an addition to the food
/// logger, not a requirement for it.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (!SupabaseConfig.isConfigured) return null;
  return Supabase.instance.client;
});

/// Auth changes as they happen: sign-in, sign-out, token refresh.
final authStateProvider = StreamProvider<AuthState?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream.empty();
  return client.auth.onAuthStateChange;
});

/// Who is signed in, or null.
///
/// Reads the client directly rather than the stream's payload so that the
/// first frame after launch already knows about a restored session —
/// `onAuthStateChange` has not necessarily emitted by then, and a false
/// "signed out" would make the dashboard drop a log it actually has.
final currentUserProvider = Provider<User?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  ref.watch(authStateProvider);
  return client.auth.currentUser;
});

final isSignedInProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

/// The sync layer, or null when there is no backend or nobody signed in.
///
/// Every caller null-checks this, which is what keeps "works offline" and
/// "works signed out" the same code path.
final nutritionSyncServiceProvider = Provider<NutritionSyncService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null || !ref.watch(isSignedInProvider)) return null;
  return NutritionSyncService(client);
});

/// Sign-in, sign-up and sign-out for the account section.
///
/// [AsyncNotifier] rather than a plain one so the sheet can show a spinner
/// and an error without tracking either itself.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  SupabaseClient get _client {
    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      throw const AuthException(SupabaseConfig.notConfiguredMessage);
    }
    return client;
  }

  Future<bool> signIn({required String email, required String password}) {
    return _run(
      () => _client.auth.signInWithPassword(email: email, password: password),
    );
  }

  Future<bool> signUp({required String email, required String password}) {
    return _run(
      () => _client.auth.signUp(email: email, password: password),
    );
  }

  Future<bool> signOut() => _run(() => _client.auth.signOut());

  /// Runs [action], parking any failure in [state] for the sheet to render.
  /// Returns whether it succeeded, so the caller can close on success
  /// without reading the state back.
  Future<bool> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    try {
      await action();
      state = const AsyncData(null);
      return true;
    } on AuthException catch (error, stack) {
      state = AsyncError(error.message, stack);
      return false;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return false;
    }
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
