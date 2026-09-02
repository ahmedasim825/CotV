import 'pc_command.dart';

/// The fastest chat model this Groq account can reach, and the id sent on
/// the wire. Measured at ~0.4s to a complete short answer, and the only
/// candidate that replies in plain prose: the gpt-oss models return their
/// text in a separate `reasoning` field, and the smaller qwen emits
/// `<think>` blocks inline.
const String groqModelId = 'qwen/qwen3.8-27b';

/// Gemini's fast reasoning model, and the id sent on the wire.
const String geminiModelId = 'gemini-3.6-flash';

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
  /// across the day's prayers, tasks and notes.
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

/// One line in the Milo panel.
class MiloMessage {
  const MiloMessage({
    required this.id,
    required this.role,
    required this.text,
    this.routing,
    this.pcResult,
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

  /// A failure that ended the turn. The turn keeps whatever text had
  /// already streamed, so a mid-answer network drop does not erase it.
  final String? error;

  final bool isStreaming;

  MiloMessage copyWith({
    String? text,
    RoutingDecision? routing,
    PcCommandResult? pcResult,
    String? error,
    bool? isStreaming,
  }) {
    return MiloMessage(
      id: id,
      role: role,
      text: text ?? this.text,
      routing: routing ?? this.routing,
      pcResult: pcResult ?? this.pcResult,
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
