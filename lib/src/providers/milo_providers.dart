import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart' show Amplitude;
import 'package:uuid/uuid.dart';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/chat_message.dart';
import '../models/daily_prayer_times.dart';
import '../models/milo_models.dart';
import '../models/subject.dart';
import '../models/task.dart';
import '../models/task_view.dart';
import '../repositories/chat_repository.dart';
import '../services/milo/gemini_client.dart';
import '../services/milo/memory_summarizer.dart';
import '../services/milo/groq_client.dart';
import '../services/milo/groq_transcription_client.dart';
import '../services/milo/local_transcription_client.dart';
import '../services/milo/milo_transcriber.dart';
import '../services/milo/milo_credentials.dart';
import '../services/milo/milo_service.dart';
import '../services/milo/milo_speech_service.dart';
import '../services/milo/milo_tools.dart';
import '../services/milo/pc_remote_service.dart';
import '../services/milo/voice_capture.dart';
import '../services/milo/wake_word_listener.dart';
import '../models/chat_session.dart';
import '../storage/local_storage.dart';
import 'chat_session_providers.dart';
import 'prayer_window_providers.dart';
import 'study_providers.dart';
import 'user_settings_providers.dart';
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

/// Speech to text, local first.
///
/// The PC agent's Faster-Whisper keeps the recording on a machine the user
/// owns; Groq's Whisper is what makes voice work at all on iOS, which has
/// no agent, and on a Windows machine whose agent is not running.
final transcriptionClientProvider = Provider<MiloTranscriber>(
  (ref) => MiloTranscriber(
    local: LocalTranscriptionClient(
      httpClient: ref.watch(miloHttpClientProvider),
    ),
    groq: GroqTranscriptionClient(
      httpClient: ref.watch(miloHttpClientProvider),
    ),
  ),
);

/// Holds the text-to-speech engine, silenced when the scope goes away so a
/// reply cannot keep talking after the panel that produced it is gone.
///
/// Windows speaks through Kokoro in the PC agent, with the OS voice behind
/// it for when the agent is not running; everywhere else speaks through the
/// OS directly, which on iOS is `AVSpeechSynthesizer` and its neural
/// voices.
final miloSpeechProvider = Provider<MiloSpeechService>((ref) {
  final system = SystemSpeechService();
  final speech = defaultTargetPlatform == TargetPlatform.windows
      ? KokoroSpeechService(
          httpClient: ref.watch(miloHttpClientProvider),
          agent: () async =>
              (await ref.read(miloSecretsProvider.future)).pcAgent,
          fallback: system,
        )
      : system;
  ref.onDispose(speech.dispose);

  // Re-applied whenever the choice changes, so picking a voice takes effect
  // on the next reply rather than the next launch.
  final name = ref.watch(
    userSettingsControllerProvider.select((s) => s.value?.voiceName),
  );
  if (name != null && name.isNotEmpty) {
    unawaited(speech.useVoice(MiloVoice(name: name)));
  }
  return speech;
});

/// Whether Milo reads its replies aloud. Persisted, so it survives a
/// restart — a setting that resets itself is one the user has to keep
/// re-making.
final miloSpeaksProvider = Provider<bool>(
  (ref) =>
      ref.watch(userSettingsControllerProvider).value?.speaksReplies ?? false,
);

/// Holds the microphone. Disposed with the scope so a recording cannot
/// outlive the app that started it.
final voiceCaptureProvider = Provider<VoiceCapture>((ref) {
  final capture = VoiceCapture();
  ref.onDispose(capture.dispose);
  return capture;
});

final pcRemoteServiceProvider = Provider<PcRemoteService>(
  (ref) => PcRemoteService(httpClient: ref.watch(miloHttpClientProvider)),
);

/// The study functions Milo may call.
final miloToolsProvider = Provider<MiloTools>(
  (ref) => MiloTools(ref.watch(studyToolTargetProvider)),
);

final miloServiceProvider = Provider<MiloService>(
  (ref) => MiloService(
    groq: ref.watch(groqClientProvider),
    gemini: ref.watch(geminiClientProvider),
    pcRemote: ref.watch(pcRemoteServiceProvider),
    tools: ref.watch(miloToolsProvider),
  ),
);

final chatMessageBoxProvider = Provider<Box<ChatMessage>>(
  (ref) => Hive.box<ChatMessage>(HiveBoxes.chatMessages),
);

/// The durable transcript. Distinct from [miloConversationProvider], which
/// is what the panel shows.
final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => HiveChatRepository(ref.watch(chatMessageBoxProvider)),
);

final memorySummarizerProvider = Provider<MemorySummarizer>(
  (ref) => MemorySummarizer(gemini: ref.watch(geminiClientProvider)),
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

  final summary = ref.watch(studySummaryProvider);
  final subjects = ref.watch(subjectListProvider).value ?? const <Subject>[];
  final study = ref.watch(studyProvider);
  final settings = ref.watch(userSettingsControllerProvider).value;

  // Only a session that is actually counting down is reported as running;
  // a paused one has no meaningful "time left" to quote.
  final running =
      study.phase == StudyPhase.running ? study.session : null;

  // The active thread's tail, capped at 15 messages / ~2000 tokens by the
  // repository. Scoped to the session rather than the whole history: two
  // unrelated conversations sharing a context window is how a model starts
  // answering the wrong one.
  final sessionId = ref.watch(activeSessionProvider);
  final recalled = sessionId == null
      ? const <ChatMessage>[]
      : ref.watch(chatSessionRepositoryProvider).contextWindow(sessionId);

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
    studyToday: [
      for (final total in summary.bySubject)
        if (total.todayMinutes > 0) total,
    ],
    studyTodayMinutes: summary.todayMinutes,
    activeStudySubject: running?.subjectName,
    activeStudyRemaining: running?.remainingAt(prayers.now),
    subjectNames: [for (final subject in subjects) subject.name],
    memorySummary: settings?.aiMemorySummary,
    recalledTurns: [
      for (final message in recalled)
        ChatTurn(
          role: message.isUser ? MiloRole.user : MiloRole.assistant,
          text: message.text,
        ),
    ],
  );
});

/// Owns the panel's transcript and the one turn that can be in flight.
///
/// The panel's transcript stays session-scoped — a relaunch opens on a
/// clean panel, which is what the user expects, and a three-day-old
/// exchange scrolled above today's is noise. Every completed turn is also
/// written through [chatRepositoryProvider], which is the durable copy:
/// the summariser condenses it, and the prompt builder recalls the last
/// few turns from it, so a new session is not starting from nothing even
/// though it looks like it.
class MiloConversationNotifier extends Notifier<MiloConversation> {
  StreamSubscription<MiloEvent>? _subscription;
  Completer<void>? _turn;
  bool _disposed = false;

  /// The prompt of the turn in flight, held so it can be persisted
  /// alongside the reply once the turn settles.
  String? _pendingPrompt;

  /// Guards the summariser: one at a time, and not again until the
  /// transcript has grown past the point the last run covered.
  ///
  /// Session-scoped, so the first qualifying turn after a launch runs one
  /// summary even if nothing has changed since the last one. That costs a
  /// single background call and saves the transcript needing a persisted
  /// high-water mark of its own.
  bool _summarizing = false;
  int _summarizedAt = 0;

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
    _pendingPrompt = text;
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
    unawaited(ref.read(miloSpeechProvider).stop());
    if (!state.isBusy) return;
    final id = state.messages.last.id;
    _abandonTurn();
    _update(id, (message) => message.copyWith(isStreaming: false));
    state = state.copyWith(isBusy: false);
  }

  /// Clears the panel.
  ///
  /// The durable transcript is left alone: this is "start a fresh
  /// conversation", not "forget me". Erasing what Milo has learned is a
  /// different and more consequential action, and it should not happen by
  /// tapping the button that tidies the screen.
  void clear() {
    unawaited(ref.read(miloSpeechProvider).stop());
    _abandonTurn();
    state = const MiloConversation();
  }

  /// Starts a fresh thread.
  ///
  /// The teardown is [clear]'s — stop speaking, abandon the turn in flight,
  /// drop the panel's messages — and then a new [ChatSession] becomes the
  /// active one. The previous thread is not held anywhere: this notifier
  /// keeps only the active window, and its messages come back off disk
  /// through an auto-disposed provider if the user opens it again.
  ///
  /// Distinct from [forget], which erases what Milo knows. Starting a new
  /// conversation and erasing the old ones are different intentions and
  /// must not be the same button.
  Future<ChatSession> newSession() async {
    clear();
    final session =
        await ref.read(chatSessionRepositoryProvider).createSession();
    ref.read(activeSessionProvider.notifier).select(session.id);
    return session;
  }

  /// Switches to [sessionId] and loads its most recent page.
  ///
  /// Only that page: the notifier holds the active thread and nothing else,
  /// which is what keeps a hundred threads in the drawer costing a hundred
  /// rows rather than a hundred histories. Older messages stay on disk and
  /// are still what the model recalls — [contextWindow] reads them there.
  Future<void> openSession(String sessionId) async {
    clear();
    ref.read(activeSessionProvider.notifier).select(sessionId);

    final stored = ref.read(chatSessionRepositoryProvider).messages(sessionId);
    if (stored.isEmpty || _disposed) return;

    state = MiloConversation(
      messages: [
        for (final message in stored)
          MiloMessage(
            id: message.id,
            role: message.isUser ? MiloRole.user : MiloRole.assistant,
            text: message.text,
          ),
      ],
    );
  }

  /// The thread being written to, creating one on the first turn.
  ///
  /// Lazy because a launch that never sends anything should not leave an
  /// empty thread in the drawer.
  Future<String> _ensureSession(String firstPrompt) async {
    final existing = ref.read(activeSessionProvider);
    if (existing != null) return existing;

    final repository = ref.read(chatSessionRepositoryProvider);
    final session = await repository.createSession(
      title: ChatSession.titleFrom(firstPrompt),
    );
    ref.read(activeSessionProvider.notifier).select(session.id);
    return session.id;
  }

  /// Erases the durable transcript and the long-term summary.
  Future<void> forget() async {
    clear();
    _summarizedAt = 0;
    await ref.read(chatRepositoryProvider).clear();
    await ref.read(chatSessionRepositoryProvider).clear();
    ref.read(activeSessionProvider.notifier).select(null);
    await ref
        .read(userSettingsControllerProvider.notifier)
        .setAiMemorySummary('');
  }

  void _apply(String id, MiloEvent event) {
    if (_disposed) return;
    _update(
      id,
      (message) => switch (event) {
        MiloRouted(:final decision) => message.copyWith(routing: decision),
        MiloPcExecuted(:final result) => message.copyWith(pcResult: result),
        MiloToolExecuted(:final summary) =>
          message.copyWith(toolNote: summary),
        MiloTextDelta(:final text) =>
          message.copyWith(text: message.text + text),
      },
    );
  }

  void _settle(String id, {Object? error}) {
    _subscription = null;
    final prompt = _pendingPrompt;
    _pendingPrompt = null;

    if (!_disposed) {
      _update(
        id,
        (message) => message.copyWith(
          isStreaming: false,
          error: error == null ? null : _describe(error),
        ),
      );
      state = state.copyWith(isBusy: false);
      if (error == null) {
        _speakIfEnabled(id);
        if (prompt != null) unawaited(_persist(id, prompt));
      }
    }
    _completeTurn();
  }

  /// Writes the finished exchange to the durable transcript, then
  /// considers a summary.
  ///
  /// Only completed turns are stored. A turn that failed produced no
  /// answer, and half an exchange in the history is worse than none: the
  /// next session would recall a question Milo never answered.
  Future<void> _persist(String replyId, String prompt) async {
    final reply = state.messages.where((m) => m.id == replyId).firstOrNull;
    final answer = reply?.text.trim() ?? '';
    if (answer.isEmpty) return;

    final repository = ref.read(chatSessionRepositoryProvider);
    final now = DateTime.now().toUtc();
    try {
      final sessionId = await _ensureSession(prompt);
      await repository.append(
        ChatMessage(
          id: _uuid.v4(),
          sessionId: sessionId,
          isUser: true,
          text: prompt,
          timestamp: now,
        ),
      );
      await repository.append(
        ChatMessage(
          id: replyId,
          sessionId: sessionId,
          isUser: false,
          text: answer,
          // A millisecond after the prompt, so sorting by timestamp can
          // never put the answer before the question it answers. A
          // microsecond would not survive the column, which stores millis.
          timestamp: now.add(const Duration(milliseconds: 1)),
        ),
      );
    } catch (_) {
      // A transcript that fails to write must not fail the turn: the
      // answer is already on screen and the user is reading it.
      return;
    }

    unawaited(_summarizeIfDue());
  }

  /// Rewrites the long-term memory in the background.
  ///
  /// Fire-and-forget by construction: nothing awaits this, and it starts
  /// only after the turn has settled, so a slow or failing summariser can
  /// never be felt in the panel. A failure leaves the previous summary
  /// exactly as it was, which matters because Gemini has been returning
  /// 503s on this account and a blank memory is worse than a stale one.
  Future<void> _summarizeIfDue() async {
    if (_summarizing || _disposed) return;

    final sessionId = ref.read(activeSessionProvider);
    if (sessionId == null) return;

    final repository = ref.read(chatSessionRepositoryProvider);
    final summarizer = ref.read(memorySummarizerProvider);
    final count = repository.messageCount(sessionId);
    if (!summarizer.shouldSummarize(
      messageCount: count,
      lastSummarizedAt: _summarizedAt,
    )) {
      return;
    }

    _summarizing = true;
    try {
      final key = (await ref.read(miloSecretsProvider.future)).geminiApiKey;
      if (key == null || _disposed) return;

      final settings = ref.read(userSettingsControllerProvider).value;
      final summary = await summarizer.summarize(
        apiKey: key,
        messages: repository.messages(
          sessionId,
          limit: summarizer.windowSize,
        ),
        previous: settings?.aiMemorySummary,
      );
      if (_disposed || summary.isEmpty) return;

      await ref
          .read(userSettingsControllerProvider.notifier)
          .setAiMemorySummary(summary);

      // Marked only on success, so a failed run is retried on the next
      // turn rather than skipped until the transcript grows again.
      _summarizedAt = count;
    } catch (_) {
      // Nothing to report and nothing to recover: the previous summary
      // stands, and the next turn tries again.
    } finally {
      _summarizing = false;
    }
  }

  /// Reads the finished reply aloud, if the user asked for that.
  ///
  /// Spoken at the end rather than per chunk: tokens arrive in fragments
  /// that do not end on word boundaries, and feeding those to a synthesiser
  /// one at a time produces stuttering rather than speech.
  void _speakIfEnabled(String id) {
    if (!ref.read(miloSpeaksProvider)) return;
    final message = state.messages.where((m) => m.id == id).firstOrNull;
    final text = message?.text.trim() ?? '';
    if (text.isEmpty) return;
    // Deliberately not awaited: a turn is finished when its text is on
    // screen, and nothing downstream should wait on the speaker.
    unawaited(ref.read(miloSpeechProvider).speak(text));
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

/// Drives the mic button: record, transcribe, then hand the text to the
/// conversation exactly as if it had been typed.
///
/// Voice is an input path, not a second assistant. Everything downstream —
/// wake-word stripping, routing, PC execution — is the text pipeline, so a
/// spoken command and a typed one cannot drift apart in behaviour.
class MiloVoiceNotifier extends Notifier<MiloVoiceState> {
  StreamSubscription<Amplitude>? _levels;
  bool _disposed = false;

  @override
  MiloVoiceState build() {
    ref.onDispose(() {
      _disposed = true;
      _levels?.cancel();
    });
    return const MiloVoiceState();
  }

  /// Starts listening, or stops and sends what was heard.
  Future<void> toggle() async {
    switch (state.phase) {
      case MiloVoicePhase.idle:
        await _startListening();
      case MiloVoicePhase.listening:
        await _finish();
      case MiloVoicePhase.transcribing:
        // Whisper is already working; a second tap would orphan it.
        break;
    }
  }

  Future<void> _startListening() async {
    // Milo has to stop talking before the microphone opens, or the next
    // thing Whisper transcribes is Milo's own last reply.
    await ref.read(miloSpeechProvider).stop();

    final capture = ref.read(voiceCaptureProvider);
    state = const MiloVoiceState(phase: MiloVoicePhase.listening);
    try {
      await capture.start();
    } on Object catch (error) {
      state = MiloVoiceState(error: _describe(error));
      return;
    }

    _levels = capture.amplitude.listen((amplitude) {
      if (_disposed) return;
      state = state.copyWith(level: _normalise(amplitude.current));
    });
  }

  Future<void> _finish() async {
    await _levels?.cancel();
    _levels = null;
    state = state.copyWith(phase: MiloVoicePhase.transcribing, level: 0);

    try {
      final bytes = await ref.read(voiceCaptureProvider).stopAndRead();
      if (bytes == null || bytes.isEmpty) {
        state = const MiloVoiceState();
        return;
      }

      final secrets = await ref.read(miloSecretsProvider.future);
      final text = await ref.read(transcriptionClientProvider).transcribe(
            bytes: bytes,
            agent: secrets.pcAgent,
            groqApiKey: secrets.groqApiKey,
          );
      if (_disposed) return;

      // Whisper returns punctuation for silence ("." or "you"), so an
      // utterance with no letters in it is treated as nothing said.
      if (!RegExp(r'[a-zA-Z]').hasMatch(text)) {
        state = const MiloVoiceState();
        return;
      }

      state = const MiloVoiceState();
      await ref.read(miloConversationProvider.notifier).send(text);
    } on Object catch (error) {
      if (_disposed) return;
      state = MiloVoiceState(error: _describe(error));
    }
  }

  /// Throws the recording away without transcribing it.
  Future<void> cancel() async {
    await _levels?.cancel();
    _levels = null;
    await ref.read(voiceCaptureProvider).cancel();
    if (!_disposed) state = const MiloVoiceState();
  }

  void clearError() => state = state.copyWith(clearError: true);

  /// Amplitude arrives in dBFS, roughly -60 (silence) to 0 (clipping).
  double _normalise(double dbfs) {
    const floor = -45.0;
    if (!dbfs.isFinite || dbfs <= floor) return 0;
    return ((dbfs - floor) / -floor).clamp(0.0, 1.0);
  }

  String _describe(Object error) => error is MiloException
      ? error.message
      : 'Milo could not hear that: $error';
}

final miloVoiceProvider =
    NotifierProvider<MiloVoiceNotifier, MiloVoiceState>(MiloVoiceNotifier.new);

/// Owns the always-on microphone. Separate from [voiceCaptureProvider]
/// because the two cannot hold the input device at once.
final wakeWordListenerProvider = Provider<WakeWordListener>((ref) {
  final listener = WakeWordListener();
  ref.onDispose(listener.dispose);
  return listener;
});

/// Whether always-on listening is armed, from the persisted setting.
final miloListensProvider = Provider<bool>(
  (ref) =>
      ref.watch(userSettingsControllerProvider).value?.listensForWakeWord ??
      false,
);

/// Whether always-on listening is actually running, and why not if it is
/// not. Distinct from the *setting*, which only says what was asked for.
class WakeWordStatus {
  const WakeWordStatus({this.armed = false, this.error});

  final bool armed;
  final String? error;
}

/// Runs always-on listening: hears an utterance, decides whether it was
/// addressed to Milo, and sends it if so.
///
/// Kept out of [MiloVoiceNotifier] because the two compete for the
/// microphone. This one yields: a deliberate tap always wins over
/// overhearing, and listening resumes when the tap is done.
class WakeWordNotifier extends Notifier<WakeWordStatus> {
  StreamSubscription<Uint8List>? _utterances;
  bool _disposed = false;
  bool _busy = false;

  /// Whether the microphone has ever been claimed.
  ///
  /// Guards the teardown path: reading [wakeWordListenerProvider]
  /// constructs an [AudioRecorder], and that reaches the platform even when
  /// nothing is recording. Tearing down something never set up would take
  /// hold of the microphone precisely when the feature is switched off.
  bool _everArmed = false;

  @override
  WakeWordStatus build() {
    ref.onDispose(() {
      _disposed = true;
      _utterances?.cancel();
    });

    // Arms and disarms itself from the setting, and stands down whenever
    // push-to-talk has the microphone.
    final wanted = ref.watch(miloListensProvider);
    final pushToTalkBusy = ref.watch(miloVoiceProvider).isBusy;

    if (wanted && !pushToTalkBusy) {
      unawaited(_arm());
    } else {
      unawaited(_disarm());
    }
    return WakeWordStatus(armed: wanted && !pushToTalkBusy);
  }

  Future<void> _arm() async {
    if (_utterances != null || _disposed) return;
    _everArmed = true;
    final listener = ref.read(wakeWordListenerProvider);
    try {
      final stream = await listener.start();
      if (_disposed) {
        await listener.stop();
        return;
      }
      _utterances = stream.listen(_onUtterance, onError: (_) {});
      state = const WakeWordStatus(armed: true);
    } on Object catch (error) {
      // Reported, not swallowed. Silence here once cost a whole debugging
      // session: the model never loaded, nothing said so, and the symptom
      // was indistinguishable from the wake word simply not triggering.
      state = WakeWordStatus(
        armed: false,
        error: 'Milo could not start listening: $error',
      );
    }
  }

  Future<void> _disarm() async {
    if (!_everArmed) return;
    await _utterances?.cancel();
    _utterances = null;
    await ref.read(wakeWordListenerProvider).stop();
  }

  Future<void> _onUtterance(Uint8List wav) async {
    // One at a time: transcribing is slower than talking, so a second
    // command arriving mid-flight is dropped rather than queued behind one
    // the user has already stopped waiting for.
    if (_busy || _disposed) return;
    _busy = true;
    try {
      final secrets = await ref.read(miloSecretsProvider.future);
      if (secrets.pcAgent == null && secrets.groqApiKey == null) return;

      final transcript =
          await ref.read(transcriptionClientProvider).transcribe(
                bytes: wav,
                agent: secrets.pcAgent,
                groqApiKey: secrets.groqApiKey,
              );
      if (_disposed || transcript.isEmpty) return;

      // The wake word was matched on device, so this audio is already known
      // to be addressed to Milo. It is still stripped, because the spotter
      // hands over the whole utterance including the phrase that triggered
      // it, and "Hey Milo open Spotify" must reach the router as
      // "open Spotify".
      final command = MiloService.stripWakeWord(transcript);
      if (!RegExp(r'[a-zA-Z]').hasMatch(command)) return;
      await ref.read(miloConversationProvider.notifier).send(command);
    } on Object {
      // Surfacing this would mean an error appearing in the panel while the
      // user is looking at something else entirely. The wake word can be
      // said again.
    } finally {
      _busy = false;
    }
  }
}

final wakeWordProvider =
    NotifierProvider<WakeWordNotifier, WakeWordStatus>(WakeWordNotifier.new);
