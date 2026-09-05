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

/// How an auth attempt ended.
enum AuthOutcome {
  /// There is a session now. The sheet can close.
  signedIn,

  /// The account exists but needs the emailed link clicked first. The
  /// sheet stays open and says so.
  needsEmailConfirmation,

  failed,
}

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

  Future<AuthOutcome> signIn({
    required String email,
    required String password,
  }) {
    return _run(() async {
      await _client.auth.signInWithPassword(email: email, password: password);
      return AuthOutcome.signedIn;
    });
  }

  /// Creates the account.
  ///
  /// Returns [AuthOutcome.needsEmailConfirmation] when the project has
  /// email confirmation switched on, which is the Supabase default: the
  /// user is created but no session comes back until they click the link.
  /// Reporting that is the difference between a form that explains itself
  /// and one that looks like the button did nothing.
  Future<AuthOutcome> signUp({
    required String email,
    required String password,
  }) {
    return _run(() async {
      final response = await _client.auth.signUp(
        email: email,
        password: password,
      );
      return response.session == null
          ? AuthOutcome.needsEmailConfirmation
          : AuthOutcome.signedIn;
    });
  }

  Future<AuthOutcome> signOut() {
    return _run(() async {
      await _client.auth.signOut();
      return AuthOutcome.signedIn;
    });
  }

  /// Runs [action], parking any failure in [state] for the sheet to render.
  Future<AuthOutcome> _run(Future<AuthOutcome> Function() action) async {
    state = const AsyncLoading();
    try {
      final outcome = await action();
      state = const AsyncData(null);
      return outcome;
    } on AuthException catch (error, stack) {
      state = AsyncError(error.message, stack);
      return AuthOutcome.failed;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return AuthOutcome.failed;
    }
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);
