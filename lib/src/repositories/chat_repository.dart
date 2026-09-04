import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../models/chat_message.dart';

/// The durable copy of the conversation with Milo.
///
/// The panel's own transcript stays session-scoped — a relaunch opens on a
/// clean panel, which is what the user expects. This is what survives it,
/// and it exists for two readers: the summariser, which needs a history to
/// condense, and the prompt builder, which recalls the last few turns so a
/// new session does not start knowing nothing.
abstract class ChatRepository {
  /// Appends one turn.
  Future<void> append(ChatMessage message);

  /// The [count] most recent turns, oldest first.
  List<ChatMessage> recent(int count);

  /// How many turns have ever been stored.
  int get count;

  Future<void> clear();
}

class HiveChatRepository implements ChatRepository {
  HiveChatRepository(this._box);

  final Box<ChatMessage> _box;

  @override
  Future<void> append(ChatMessage message) => _box.put(message.id, message);

  @override
  List<ChatMessage> recent(int count) {
    if (count <= 0) return const [];

    // Sorted by timestamp rather than trusted to insertion order: Hive
    // returns values in key order, and the keys are UUIDs.
    final all = _box.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return all.length <= count
        ? List.unmodifiable(all)
        : List.unmodifiable(all.sublist(all.length - count));
  }

  @override
  int get count => _box.length;

  @override
  Future<void> clear() => _box.clear();
}
