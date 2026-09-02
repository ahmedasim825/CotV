import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/milo_models.dart';
import 'sse_stream.dart';

/// Streaming chat against Groq's OpenAI-compatible endpoint.
///
/// Carries the low-latency half of Milo's routing: short commands and
/// lookups, where the time to the first token is what the request is
/// being judged on.
class GroqClient {
  /// [model] stays overridable so a build can point at a larger Groq model
  /// without touching the routing code.
  GroqClient({required http.Client httpClient, this.model = groqModelId})
      : _http = httpClient;

  static final Uri endpoint =
      Uri.parse('https://api.groq.com/openai/v1/chat/completions');

  /// Groq's ceiling for one reply. Generous enough for a paragraph, low
  /// enough that a runaway generation cannot bill indefinitely.
  static const int maxTokens = 800;

  final http.Client _http;
  final String model;

  /// Streams the reply to [prompt] as it is generated.
  ///
  /// [history] is the conversation so far, oldest first, and does not
  /// include [prompt].
  Stream<String> streamReply({
    required String apiKey,
    required String systemPrompt,
    required List<ChatTurn> history,
    required String prompt,
  }) async* {
    final request = http.Request('POST', endpoint)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'max_tokens': maxTokens,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          for (final turn in history)
            {
              'role': turn.role == MiloRole.user ? 'user' : 'assistant',
              'content': turn.text,
            },
          {'role': 'user', 'content': prompt},
        ],
      });

    final response = await _http.send(request);
    if (response.statusCode != 200) {
      throw MiloException(
        _failureMessage(response.statusCode, await _readError(response)),
      );
    }

    await for (final event in decodeSseJson(response.stream)) {
      final choices = event['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final delta = (choices.first as Map<String, dynamic>)['delta'];
      if (delta is! Map<String, dynamic>) continue;
      final content = delta['content'];
      if (content is String && content.isNotEmpty) yield content;
    }
  }

  /// Groq reports errors as `{"error": {"message": ...}}`. Falls back to
  /// the raw body, which is what a proxy or gateway in front of the API
  /// would return instead.
  Future<String?> _readError(http.StreamedResponse response) async {
    final body = await response.stream.bytesToString();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        if (message is String) return message;
      }
    } on FormatException {
      // Not JSON. The body itself is the best detail available.
    }
    return body.isEmpty ? null : body;
  }

  String _failureMessage(int status, String? detail) {
    switch (status) {
      case 401:
      case 403:
        return 'Groq rejected the API key. Check it in Milo settings.';
      case 429:
        return 'Groq is rate limiting this key. Try again shortly, or ask '
            'something that routes to Gemini.';
      case 404:
        return 'Groq has no model called "$model".';
      default:
        return 'Groq returned $status${detail == null ? '.' : ': $detail'}';
    }
  }
}
