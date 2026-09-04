import 'package:hive_ce/hive_ce.dart';

part 'chat_message.g.dart';

/// One stored turn of conversation with Milo.
///
/// The panel's own transcript is session-scoped and always has been. This is
/// the durable copy, and it exists for one reason: the summariser needs a
/// history to condense, and the next launch needs the summary. Without
/// persistence Milo starts every session knowing nothing.
@HiveType(typeId: 10)
class ChatMessage {
  ChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
  });

  @HiveField(0)
  final String id;

  /// True for the user's turn, false for Milo's.
  ///
  /// A bool rather than an enum because Hive stores enums by index, and an
  /// index is exactly the thing that breaks when a case is inserted.
  @HiveField(1)
  final bool isUser;

  @HiveField(2)
  final String text;

  @HiveField(3)
  final DateTime timestamp;

  @override
  String toString() =>
      'ChatMessage(${isUser ? 'user' : 'milo'}, ${text.length} chars)';
}
