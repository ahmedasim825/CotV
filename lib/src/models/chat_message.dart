import 'package:hive_ce/hive_ce.dart';

part 'chat_message.g.dart';

/// One stored turn of conversation with Milo.
///
/// Lives in SQLite, in `chat_messages`, keyed to a [ChatSession]. It keeps
/// its Hive annotations for exactly one reason: the box they describe still
/// holds every message written before threads existed, and the one-time
/// import has to be able to read it. Nothing writes to that box any more.
///
/// [sessionId] and [tokensUsed] are deliberately *not* Hive fields. A row
/// old enough to be in the box predates both, so there would be nothing for
/// them to read.
@HiveType(typeId: 10)
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.sessionId = '',
    this.tokensUsed,
  });

  @HiveField(0)
  final String id;

  /// True for the user's turn, false for Milo's.
  ///
  /// A bool rather than an enum because Hive stores enums by index, and an
  /// index is exactly the thing that breaks when a case is inserted. SQLite
  /// stores the same distinction as [role], which is a string and has no
  /// such problem.
  @HiveField(1)
  final bool isUser;

  @HiveField(2)
  final String text;

  @HiveField(3)
  final DateTime timestamp;

  /// The thread this turn belongs to. Empty only on a message that has not
  /// been assigned one yet — which is every row the importer reads.
  final String sessionId;

  /// What the turn actually cost, when the provider reported it.
  ///
  /// Null means unknown, and the context window falls back to estimating.
  /// Stored per message rather than per session so the estimate can be
  /// replaced with real numbers without a schema change.
  final int? tokensUsed;

  /// The stored form of [isUser]. A string, because it goes to a server
  /// eventually and `role` is what every chat API calls this.
  String get role => isUser ? 'user' : 'assistant';

  /// Roughly what this turn costs the model's context.
  ///
  /// Four characters to the token is the usual rule of thumb for English
  /// and is wrong for code and for Arabic transliteration alike. It is used
  /// only to decide where to cut a window that is already capped by message
  /// count, so being off by a third costs a message either way — not a
  /// failed request. [tokensUsed] replaces it whenever the provider said.
  int get approximateTokens => tokensUsed ?? (text.length / 4).ceil();

  ChatMessage copyWith({String? sessionId, int? tokensUsed}) => ChatMessage(
        id: id,
        isUser: isUser,
        text: text,
        timestamp: timestamp,
        sessionId: sessionId ?? this.sessionId,
        tokensUsed: tokensUsed ?? this.tokensUsed,
      );

  @override
  String toString() =>
      'ChatMessage($role, ${text.length} chars)';
}
