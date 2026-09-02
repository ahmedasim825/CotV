import 'dart:convert';

/// Decodes a `text/event-stream` body into the parsed JSON of each event's
/// `data` field.
///
/// Both engines stream over SSE, so the framing lives here once rather than
/// twice: Groq's OpenAI-compatible endpoint and Gemini's
/// `streamGenerateContent?alt=sse` differ only in the shape of the JSON
/// inside each event, which is what [GroqClient] and [GeminiClient] pull
/// apart themselves.
///
/// Follows the event-stream rules that matter here: `data` lines accumulate
/// until a blank line dispatches the event, one optional space after the
/// colon is dropped, and comment lines (`:` first) are ignored. OpenAI's
/// `[DONE]` sentinel ends the stream; Gemini simply closes the body, which
/// ends it too.
Stream<Map<String, dynamic>> decodeSseJson(Stream<List<int>> body) async* {
  final data = <String>[];

  Map<String, dynamic>? dispatch() {
    if (data.isEmpty) return null;
    final payload = data.join('\n');
    data.clear();
    if (payload == '[DONE]') return null;
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  await for (final line
      in body.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      final event = dispatch();
      if (event != null) yield event;
      continue;
    }
    if (line.startsWith(':')) continue;
    if (!line.startsWith('data:')) continue;

    final value = line.substring('data:'.length);
    if (value == ' [DONE]' || value == '[DONE]') return;
    data.add(value.startsWith(' ') ? value.substring(1) : value);
  }

  // A body that closes without a trailing blank line still owes us its
  // last event.
  final trailing = dispatch();
  if (trailing != null) yield trailing;
}
