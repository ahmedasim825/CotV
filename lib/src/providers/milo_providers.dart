import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/daily_prayer_times.dart';
import '../models/milo_models.dart';
import '../models/task.dart';
import '../models/task_view.dart';
import '../services/milo/gemini_client.dart';
import '../services/milo/groq_client.dart';
import '../services/milo/milo_credentials.dart';
import '../services/milo/milo_service.dart';
import '../services/milo/pc_remote_service.dart';
import 'prayer_window_providers.dart';
import 'task_providers.dart';

const _uuid = Uuid();

/// One HTTP client behind both engines and the PC bridge, so connections to
/// the same host are reused across turns instead of being renegotiated.
final miloHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final miloCredentialsProvider =
    Provider<MiloCredentials>((ref) => MiloCredentials());

/// The keys, read once and cached. The settings sheet invalidates this
/// after a save, which is what makes a newly entered key take effect
/// without a relaunch.
final miloSecretsProvider = FutureProvider<MiloSecrets>(
  (ref) => ref.watch(miloCredentialsProvider).load(),
);

final groqClientProvider = Provider<GroqClient>(
  (ref) => GroqClient(httpClient: ref.watch(miloHttpClientProvider)),
);

final geminiClientProvider = Provider<GeminiClient>(
  (ref) => GeminiClient(httpClient: ref.watch(miloHttpClientProvider)),
);

final pcRemoteServiceProvider = Provider<PcRemoteService>(
  (ref) => PcRemoteService(httpClient: ref.watch(miloHttpClientProvider)),
);

final miloServiceProvider = Provider<MiloService>(
  (ref) => MiloService(
    groq: ref.watch(groqClientProvider),
    gemini: ref.watch(geminiClientProvider),
    pcRemote: ref.watch(pcRemoteServiceProvider),
  ),
);

/// Due date first (undated tasks last), then priority — the same order the
/// task list itself uses, so Milo names the tasks in the order the user
/// sees them.
int _byDueThenPriority(Task a, Task b) {
  final aDue = a.dueDate;
  final bDue = b.dueDate;
  if (aDue != null && bDue != null) {
    final byDue = aDue.compareTo(bDue);
    if (byDue != 0) return byDue;
  } else if (aDue != null) {
    return -1;
  } else if (bDue != null) {
    return 1;
  }
  return a.priority.rank.compareTo(b.priority.rank);
}

/// How many open tasks Milo is told about by name. Enough to answer "what
/// should I do next", short enough not to spend the prompt on a backlog.
const int _namedTaskLimit = 5;

/// The snapshot each turn is answered against.
final miloContextProvider = Provider.autoDispose<MiloContext>((ref) {
  final prayers = ref.watch(prayerNowStateProvider);
  final tasks = ref.watch(taskListProvider).value ?? const <Task>[];
  final open = tasks.where((task) => !task.isCompleted).toList()
    ..sort(_byDueThenPriority);

  return MiloContext(
    now: prayers.now,
    nextPrayer: prayers.nextAdhan.prayer.displayName,
    nextPrayerTime: prayers.nextAdhan.time,
    isLockedOut: prayers.isLockedOut,
    openTaskCount: open.length,
    nextTaskTitles: open
        .take(_namedTaskLimit)
        .map((task) => task.title)
        .toList(growable: false),
  );
});

/// Owns the panel's transcript and the one turn that can be in flight.
///
/// The transcript is session-scoped: it is not written to Hive, because a
/// half-remembered exchange from three days ago is worse context than none,
/// and the keys it was produced with may since have changed.
class MiloConversationNotifier extends Notifier<MiloConversation> {
  StreamSubscription<MiloEvent>? _subscription;
  Completer<void>? _turn;
  bool _disposed = false;

  @override
  MiloConversation build() {
    ref.onDispose(() {
      _disposed = true;
      _abandonTurn();
    });
    return const MiloConversation();
  }

  /// Sends [rawText] and resolves when the turn has finished, failed or
  /// been stopped. A second call while a turn is in flight is ignored — the
  /// composer disables Send for the same reason.
  Future<void> send(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty || state.isBusy) return Future.value();

    final history = state.history;
    final replyId = _uuid.v4();
    state = state.copyWith(
      messages: [
        ...state.messages,
        MiloMessage(id: _uuid.v4(), role: MiloRole.user, text: text),
        MiloMessage(
          id: replyId,
          role: MiloRole.assistant,
          text: '',
          isStreaming: true,
        ),
      ],
      isBusy: true,
    );

    final turn = Completer<void>();
    _turn = turn;
    _start(replyId, text, history);
    return turn.future;
  }

  Future<void> _start(
    String replyId,
    String prompt,
    List<ChatTurn> history,
  ) async {
    try {
      final secrets = await ref.read(miloSecretsProvider.future);
      if (_disposed) return;

      _subscription = ref
          .read(miloServiceProvider)
          .respond(
            rawPrompt: prompt,
            secrets: secrets,
            context: ref.read(miloContextProvider),
            history: history,
          )
          .listen(
            (event) => _apply(replyId, event),
            onError: (Object error) => _settle(replyId, error: error),
            onDone: () => _settle(replyId),
            cancelOnError: true,
          );
    } on Object catch (error) {
      // Reading the keys can fail on its own (a locked Keychain), before
      // the stream that would otherwise report it exists.
      _settle(replyId, error: error);
    }
  }

  /// Ends the turn early, keeping whatever has streamed so far.
  void stop() {
    if (!state.isBusy) return;
    final id = state.messages.last.id;
    _abandonTurn();
    _update(id, (message) => message.copyWith(isStreaming: false));
    state = state.copyWith(isBusy: false);
  }

  void clear() {
    _abandonTurn();
    state = const MiloConversation();
  }

  void _apply(String id, MiloEvent event) {
    if (_disposed) return;
    _update(
      id,
      (message) => switch (event) {
        MiloRouted(:final decision) => message.copyWith(routing: decision),
        MiloPcExecuted(:final result) => message.copyWith(pcResult: result),
        MiloTextDelta(:final text) =>
          message.copyWith(text: message.text + text),
      },
    );
  }

  void _settle(String id, {Object? error}) {
    _subscription = null;
    if (!_disposed) {
      _update(
        id,
        (message) => message.copyWith(
          isStreaming: false,
          error: error == null ? null : _describe(error),
        ),
      );
      state = state.copyWith(isBusy: false);
    }
    _completeTurn();
  }

  /// A [MiloException] already carries a message written for the panel.
  /// Anything else is unexpected, so it says so rather than pretending to
  /// be advice.
  String _describe(Object error) => error is MiloException
      ? error.message
      : 'Milo could not finish that: $error';

  void _abandonTurn() {
    _subscription?.cancel();
    _subscription = null;
    _completeTurn();
  }

  void _completeTurn() {
    final turn = _turn;
    _turn = null;
    if (turn != null && !turn.isCompleted) turn.complete();
  }

  void _update(String id, MiloMessage Function(MiloMessage) transform) {
    state = state.copyWith(
      messages: [
        for (final message in state.messages)
          if (message.id == id) transform(message) else message,
      ],
    );
  }
}

/// Kept alive rather than auto-disposed: closing the panel should not
/// discard the conversation the user is in the middle of.
final miloConversationProvider =
    NotifierProvider<MiloConversationNotifier, MiloConversation>(
  MiloConversationNotifier.new,
);
