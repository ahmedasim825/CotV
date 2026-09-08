/// One conversation thread with Milo.
///
/// Plain Dart with no Hive adapter: sessions live in SQLite, and the whole
/// point of the split is that the drawer can list a hundred of them without
/// reading a single message body.
class ChatSession {
  const ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
  });

  /// What a thread is called before it has been named or renamed.
  ///
  /// Short-lived by design — [titleFrom] replaces it with the first thing
  /// the user actually said, so the drawer is never a column of these.
  static const String untitled = 'New chat';

  /// How much of the first message becomes the title.
  static const int titleLength = 40;

  final String id;
  final String title;
  final DateTime createdAt;

  /// Last message, not last edit — this is what the drawer orders by, and
  /// "when did I last talk about this" is the question being answered.
  final DateTime updatedAt;

  /// Filled by the repository's list query, which counts rows rather than
  /// loading them. Zero on a session built in memory.
  final int messageCount;

  bool get isEmpty => messageCount == 0;

  /// A title derived from the first thing said in the thread.
  ///
  /// Cut on a word boundary where one is close enough to the limit, so a
  /// title ends on a word rather than mid-syllable.
  static String titleFrom(String firstMessage) {
    final clean = firstMessage.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return untitled;
    if (clean.length <= titleLength) return clean;

    final cut = clean.substring(0, titleLength);
    final lastSpace = cut.lastIndexOf(' ');
    final trimmed = lastSpace > titleLength - 12 ? cut.substring(0, lastSpace) : cut;
    return '${trimmed.trimRight()}…';
  }

  ChatSession copyWith({String? title, DateTime? updatedAt, int? messageCount}) {
    return ChatSession(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  @override
  String toString() => 'ChatSession($id, "$title", $messageCount messages)';
}
