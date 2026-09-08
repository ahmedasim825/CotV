import 'pc_command.dart';

/// The fastest chat model this Groq account can reach, and the id sent on
/// the wire. Measured at ~0.4s to a complete short answer, and the only
/// candidate that replies in plain prose: the gpt-oss models return their
/// text in a separate `reasoning` field, and the smaller qwen emits
/// `<think>` blocks inline.
const String groqModelId = 'qwen/qwen3.8-27b';

/// Gemini's fast reasoning model, and the id sent on the wire.
const String geminiModelId = 'gemini-2.5-flash';

/// Groq's speech model, and the id sent on the wire.
///
/// The turbo variant is the latency-optimised Whisper: a spoken sentence
/// measured 1.7s end to end against 1.1s for full `whisper-large-v3`, which
/// is inside the noise for an utterance this short, so the tie goes to the
/// model built for streaming-speed workloads.
const String whisperModelId = 'whisper-large-v3-turbo';

/// The Faster-Whisper checkpoint the PC agent loads when it is running.
///
/// `base.en` rather than `tiny.en`: English-only either way, and base is
/// the smallest one that hears "Maghrib" as a word rather than as three.
/// The agent takes this as a request and reports what it actually loaded,
/// so a machine short on memory can serve tiny.en without the app caring.
const String localWhisperModelId = 'base.en';

/// Kokoro's voice profile, sent to the PC agent with every line.
const String kokoroVoiceId = 'af_heart';

/// The iOS system voices Milo asks for, best first.
///
/// Both are Apple's neural voices, which is the whole reason for naming
/// any: the compact fallbacks sound like a screen reader, and there is no
/// flag that selects "neural" — only the voice's name does.
const List<String> preferredIosVoices = ['Ava', 'Zoe'];

/// Sent on every engine request.
///
/// Not cosmetic: Groq sits behind Cloudflare, which answers a request
/// carrying a default library User-Agent with `error code: 1010` and a 403
/// before it ever reaches the API. Naming the product gets through, and is
/// the honest thing to send anyway.
const String miloUserAgent = 'PrayerLockout-Milo/1.0 (Flutter)';

/// How long a reply may go without producing a byte before the turn is
/// abandoned.
///
/// Sized against a real overloaded provider rather than a guess: a Gemini
/// call measured six minutes to its first token and then answered
/// correctly. Correct is no use at that latency, because the panel has been
/// frozen for the whole of it.
///
/// Applied to the response body rather than to the decoded text, for two
/// reasons. It is where a network stall actually is; and an error raised
/// downstream of [decodeSseJson] cannot get back out, because cancelling an
/// `async*` generator suspended in an `await for` never completes.
///
/// It restarts on every chunk, so a long answer streams for as long as it
/// needs provided bytes keep arriving.
const Duration miloStallTimeout = Duration(seconds: 75);

/// Which model answered a turn.
///
/// The two engines are not interchangeable: Groq is picked for latency and
/// Gemini for reasoning depth, and the badge on every assistant turn names
/// which one ran. Nothing in the UI may claim an engine that did not.
enum MiloEngine {
  /// Groq — first token in a few hundred milliseconds, which is what makes
  /// a spoken-style command feel instant.
  groq(model: groqModelId, badge: 'Groq Instant'),

  /// Gemini — slower to start, but holds a longer chain of reasoning
  /// across the day's prayers, tasks and notes, and is the only one asked
  /// medical questions.
  gemini(model: geminiModelId, badge: 'Gemini Deep');

  const MiloEngine({required this.model, required this.badge});

  /// The provider's model id, sent on the wire.
  final String model;

  /// What the routing rail calls this engine.
  final String badge;
}

/// The engine choice plus the rule that produced it.
///
/// [reason] is shown under the routing rail rather than kept for logs: the
/// user is entitled to know why a request went to the slower model, and it
/// is the only way to tell a routing mistake from a model mistake.
class RoutingDecision {
  const RoutingDecision({required this.engine, required this.reason});

  final MiloEngine engine;
  final String reason;
}

/// Who said a line.
enum MiloRole { user, assistant }

/// One turn of a conversation with a chat model, in the shape both clients
/// convert from.
class ChatTurn {
  const ChatTurn({required this.role, required this.text});

  final MiloRole role;
  final String text;
}

/// A function call the model asked for, reassembled from the stream.
///
/// Engine-neutral on purpose: only [GroqClient] knows the wire framing that
/// produced it, and only [MiloTools] knows what to do with it.
class MiloToolCall {
  const MiloToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// The provider's id for this call. It has to travel back on the tool
  /// result message, or the model cannot match answer to question.
  final String id;

  final String name;

  /// The decoded arguments. Decoded once, at the end of the stream — see
  /// [GroqClient.streamTurn].
  final Map<String, dynamic> arguments;

  /// [key] as a trimmed string, or null when absent or not a string.
  String? stringArg(String key) {
    final value = arguments[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  /// [key] as an int, accepting the number-shaped string models sometimes
  /// emit for an integer parameter.
  int? intArg(String key) {
    final value = arguments[key];
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  @override
  String toString() => 'MiloToolCall($name, $arguments)';
}

/// A round of tool calls and what they returned, replayed to the model so
/// it can answer with the results in hand.
class MiloToolExchange {
  const MiloToolExchange({required this.calls, required this.results});

  /// What the model asked for, in the order it asked.
  final List<MiloToolCall> calls;

  /// Each call's result, keyed by [MiloToolCall.id].
  final Map<String, String> results;
}

/// One line in the Milo panel.
class MiloMessage {
  const MiloMessage({
    required this.id,
    required this.role,
    required this.text,
    this.routing,
    this.pcResult,
    this.toolNote,
    this.error,
    this.isStreaming = false,
  });

  final String id;
  final MiloRole role;

  /// Grows chunk by chunk while [isStreaming] is true.
  final String text;

  /// Set on an assistant turn as soon as the router has chosen, which is
  /// before the first token arrives.
  final RoutingDecision? routing;

  /// Set when the turn carried a PC command, whether or not it succeeded.
  final PcCommandResult? pcResult;

  /// What a study tool did on this turn, in one sentence.
  ///
  /// Shown as its own receipt rather than left to the reply: the model is
  /// asked to describe the action, and a model describing an action it did
  /// not verify is exactly what a receipt is for.
  final String? toolNote;

  /// A failure that ended the turn. The turn keeps whatever text had
  /// already streamed, so a mid-answer network drop does not erase it.
  final String? error;

  final bool isStreaming;

  MiloMessage copyWith({
    String? text,
    RoutingDecision? routing,
    PcCommandResult? pcResult,
    String? toolNote,
    String? error,
    bool? isStreaming,
  }) {
    return MiloMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      routing: routing ?? this.routing,
      pcResult: pcResult ?? this.pcResult,
      toolNote: toolNote ?? this.toolNote,
      error: error ?? this.error,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}

/// Everything the panel renders.
class MiloConversation {
  const MiloConversation({this.messages = const [], this.isBusy = false});

  final List<MiloMessage> messages;

  /// A turn is in flight — the composer shows Stop instead of Send.
  final bool isBusy;

  bool get isEmpty => messages.isEmpty;

  /// The turns to send as history, oldest first, excluding any turn that
  /// failed before producing text.
  List<ChatTurn> get history => [
        for (final message in messages)
          if (message.text.isNotEmpty)
            ChatTurn(role: message.role, text: message.text),
      ];

  MiloConversation copyWith({List<MiloMessage>? messages, bool? isBusy}) {
    return MiloConversation(
      messages: messages ?? this.messages,
      isBusy: isBusy ?? this.isBusy,
    );
  }
}

/// A failure the user can act on: a missing key, a rejected key, a rate
/// limit, an unreachable host. [message] is written for the panel, so it
/// says what to do rather than quoting a status line.
class MiloException implements Exception {
  MiloException(this.message);

  final String message;

  @override
  String toString() => 'MiloException: $message';
}

/// Where a spoken turn has got to.
enum MiloVoicePhase {
  idle,

  /// The microphone is open and audio is being written.
  listening,

  /// Recording stopped, waiting on Whisper.
  transcribing,
}

/// The state of the mic button.
class MiloVoiceState {
  const MiloVoiceState({
    this.phase = MiloVoicePhase.idle,
    this.level = 0,
    this.error,
  });

  final MiloVoicePhase phase;

  /// Loudness right now, 0 to 1, for the ring around the mic button.
  ///
  /// Live feedback is not decoration here: without it there is no way to
  /// tell "Milo is listening and hears you" from "the microphone is dead",
  /// and the difference only becomes visible after the request has failed.
  final double level;

  /// Set when the last attempt failed, and cleared when a new one starts.
  final String? error;

  bool get isBusy => phase != MiloVoicePhase.idle;

  MiloVoiceState copyWith({
    MiloVoicePhase? phase,
    double? level,
    String? error,
    bool clearError = false,
  }) =>
      MiloVoiceState(
        phase: phase ?? this.phase,
        level: level ?? this.level,
        error: clearError ? null : (error ?? this.error),
      );
}
