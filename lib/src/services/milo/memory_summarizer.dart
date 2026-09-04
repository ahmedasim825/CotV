import '../../models/chat_message.dart';
import '../../models/milo_models.dart';
import 'gemini_client.dart';

/// Distils the conversation into the few facts worth carrying forward.
///
/// Runs on Gemini rather than Groq: this is the one Milo job with no
/// latency requirement at all — nothing waits on it — and it is the kind of
/// compression the deep model is better at.
class MemorySummarizer {
  MemorySummarizer({required this.gemini, this.windowSize = 20});

  final GeminiClient gemini;

  /// How many recent turns are condensed. Twenty is roughly a session and
  /// a half — long enough to contain a preference stated once.
  final int windowSize;

  /// Whether a summary is worth running now.
  ///
  /// Two conditions, and both matter. There has to be a window's worth of
  /// conversation at all; and the transcript has to have grown past the
  /// point the last summary covered, or every message after the twentieth
  /// would trigger a call that re-reads the same history.
  bool shouldSummarize({
    required int messageCount,
    required int lastSummarizedAt,
  }) =>
      messageCount >= windowSize && messageCount > lastSummarizedAt;

  /// Rewrites the summary from [messages] and [previous].
  ///
  /// Throws [MiloException] if the call fails — the caller keeps the
  /// previous summary rather than replacing a real one with nothing.
  Future<String> summarize({
    required String apiKey,
    required List<ChatMessage> messages,
    String? previous,
  }) async {
    final transcript = [
      for (final message in messages)
        '${message.isUser ? 'User' : 'Milo'}: ${_oneLine(message.text)}',
    ].join('\n');

    final buffer = StringBuffer()
      ..write(
        'Write what is worth remembering about this user for future '
        'conversations: their subjects, study habits, routine, stated '
        'preferences, and anything they have said about themselves. ',
      )
      ..write(
        'At most six short lines, each a plain statement of fact. No '
        'preamble, no headings, no speculation. ',
      )
      ..write(
        'Leave out anything that was only true for one day — a single '
        'session\'s length, a task due tomorrow. ',
      )
      ..write(
        'If there is nothing worth remembering, reply with the single word '
        'NOTHING.',
      );

    final existing = previous?.trim();
    final prompt = StringBuffer();
    if (existing != null && existing.isNotEmpty) {
      prompt
        ..writeln('What is already known:')
        ..writeln(existing)
        ..writeln()
        ..writeln(
          'Update it against the conversation below — keep what still '
          'holds, correct what has changed, add what is new.',
        )
        ..writeln();
    }
    prompt
      ..writeln('CONVERSATION')
      ..write(transcript);

    final answer = StringBuffer();
    await for (final delta in gemini.streamReply(
      apiKey: apiKey,
      systemPrompt: buffer.toString(),
      history: const [],
      prompt: prompt.toString(),
    )) {
      answer.write(delta);
    }

    final summary = answer.toString().trim();
    if (summary.isEmpty) {
      throw MiloException('The summariser returned nothing.');
    }
    // The model's own way of saying there was nothing to keep. Returned as
    // an empty string so the caller can tell it from a real summary.
    return summary.toUpperCase() == 'NOTHING' ? '' : summary;
  }

  String _oneLine(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
