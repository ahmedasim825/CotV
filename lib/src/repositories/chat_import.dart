import '../models/chat_session.dart';
import 'chat_repository.dart';
import 'chat_session_repository.dart';

/// Moves the pre-threads transcript into a session.
///
/// Everything Milo stored before this build went into one flat Hive box
/// with no notion of a thread. Discarding it would erase whatever the
/// summariser had been condensing, so it becomes one session instead.
///
/// Two properties matter more than the copy itself:
///
///   * **Atomic.** The session and its messages are written in one
///     transaction. Without that, a run that inserted the session and then
///     died would leave something the next run reads as a finished import,
///     and the messages would be lost rather than retried.
///   * **Idempotent.** A second run finds the session already there and
///     does nothing, which — given the transaction above — can only mean
///     the first run completed.
///   * **Non-destructive.** The Hive box is left exactly as it was. A
///     failed import has to be re-runnable, and it cannot be if the source
///     was cleared halfway through.
class ChatImporter {
  const ChatImporter({required this.source, required this.destination});

  /// What the imported thread is called. Not "Imported": the user never
  /// asked for an import and should not have to reason about one.
  static const String sessionTitle = 'Earlier';

  /// A fixed id, which is what makes a second run a no-op rather than a
  /// second copy.
  static const String sessionId = 'chat-imported-legacy';

  final ChatRepository source;
  final ChatSessionRepository destination;

  /// Runs the import if it has not run, and reports how many turns moved.
  ///
  /// Zero means either an empty box or an import that already happened —
  /// indistinguishable afterwards, and neither needs acting on.
  Future<int> importIfNeeded() async {
    if (destination.findById(sessionId) != null) return 0;

    final legacy = source.recent(source.count);
    if (legacy.isEmpty) return 0;

    return destination.transaction(() async {
      // Created at the first message and last touched at the most recent,
      // so the thread sorts into the drawer where it belongs in time
      // instead of jumping to the top as though it were new.
      await destination.insertSession(
        ChatSession(
          id: sessionId,
          title: sessionTitle,
          createdAt: legacy.first.timestamp.toUtc(),
          updatedAt: legacy.last.timestamp.toUtc(),
        ),
      );

      for (final message in legacy) {
        await destination.append(message.copyWith(sessionId: sessionId));
      }

      return legacy.length;
    });
  }
}
