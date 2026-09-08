import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../repositories/chat_import.dart';
import '../repositories/chat_session_repository.dart';
import '../storage/app_database.dart';
import 'milo_providers.dart';

/// The SQLite connection, opened once in `main()` and overridden here.
///
/// Throws rather than opening lazily: the database is opened before
/// `runApp` alongside Hive, and a provider that quietly opened a second
/// connection would give half the app a different WAL view of the same
/// file.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError(
    'appDatabaseProvider must be overridden with the instance opened in '
    'main(). See bootstrapAppDatabase().',
  );
});

final chatSessionRepositoryProvider = Provider<ChatSessionRepository>((ref) {
  final repository =
      SqliteChatSessionRepository(ref.watch(appDatabaseProvider));
  ref.onDispose(repository.dispose);
  return repository;
});

/// Which thread the panel is showing.
///
/// Null until the first read, which is what makes the panel open on the
/// most recent thread rather than always on a blank one.
class ActiveSessionNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? sessionId) => state = sessionId;
}

final activeSessionProvider =
    NotifierProvider<ActiveSessionNotifier, String?>(ActiveSessionNotifier.new);

/// Every thread, metadata only.
///
/// Deliberately never carries message bodies: the drawer renders titles,
/// counts and times, and a hundred threads should cost a hundred rows of
/// text rather than the whole history.
final chatSessionListProvider = StreamProvider<List<ChatSession>>(
  (ref) => ref.watch(chatSessionRepositoryProvider).watchSessions(),
);

/// What is currently typed in the drawer's search field.
class SessionSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final sessionSearchQueryProvider =
    NotifierProvider<SessionSearchQueryNotifier, String>(
  SessionSearchQueryNotifier.new,
);

final filteredSessionListProvider = Provider<List<ChatSession>>((ref) {
  final query = ref.watch(sessionSearchQueryProvider);
  final all = ref.watch(chatSessionListProvider).value ?? const <ChatSession>[];
  if (query.trim().isEmpty) return all;

  // Goes back to the repository rather than filtering [all] in Dart: the
  // search matches message bodies too, and those are exactly what the list
  // provider is built not to hold.
  return ref.watch(chatSessionRepositoryProvider).search(query);
});

/// One thread's messages, newest page first.
///
/// Auto-disposed and keyed by session, which is what bounds idle memory:
/// switching threads drops the previous one's page on the next collection
/// rather than accumulating every thread opened this session.
final sessionMessagesProvider =
    Provider.autoDispose.family<List<ChatMessage>, String>((ref, sessionId) {
  // Rebuilds when any session changes, which includes a message landing in
  // this one — append() touches the parent row's updated_at.
  ref.watch(chatSessionListProvider);
  return ref.watch(chatSessionRepositoryProvider).messages(sessionId);
});

/// Opens the database, runs the legacy import, and hands back the override
/// the root [ProviderScope] needs.
///
/// Called from `main()` beside Hive's own setup. The import runs here
/// rather than on first panel open so a user who never opens Milo still
/// gets their history moved, and so it happens once per launch at a moment
/// nothing is waiting on.
Future<AppDatabase> bootstrapAppDatabase() async {
  return AppDatabase.open();
}

/// Moves the pre-threads Hive transcript into a session, once.
///
/// Watched by the shell for the same reason the study reconciler is: a
/// provider nothing listens to is never built, and this has to run whether
/// or not the user opens the panel.
final chatImportProvider = FutureProvider<int>((ref) async {
  return ChatImporter(
    source: ref.watch(chatRepositoryProvider),
    destination: ref.watch(chatSessionRepositoryProvider),
  ).importIfNeeded();
});
