import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/milo_models.dart';
import 'sse_stream.dart';

/// Streaming chat against the Gemini generative language API.
///
/// Carries the high-complexity half of Milo's routing: planning, summaries
/// and anything that has to hold several parts of the day in mind at once.
class GeminiClient {
  GeminiClient({required http.Client httpClient, this.model = geminiModelId})
      : _http = httpClient;

  static const String _apiRoot =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Gemini's ceiling for one reply. Higher than Groq's: this engine is
  /// chosen for answers that are meant to be longer.
  static const int maxOutputTokens = 1600;

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
    // `alt=sse` switches the endpoint from a streamed JSON array to
    // event-stream framing, which is what lets the panel render partial
    // text instead of waiting for the closing bracket.
    final uri = Uri.parse('$_apiRoot/$model:streamGenerateContent?alt=sse');

    final request = http.Request('POST', uri)
      ..headers.addAll({
        // The key travels as a header, never as a query parameter: a URL
        // ends up in proxy logs and crash reports, a header does not.
        'x-goog-api-key': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
      })
      ..body = jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
        'contents': [
          for (final turn in history)
            {
              // Gemini names the assistant side "model"; everything else in
              // this app calls it the assistant.
              'role': turn.role == MiloRole.user ? 'user' : 'model',
              'parts': [
                {'text': turn.text},
              ],
            },
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {'maxOutputTokens': maxOutputTokens},
      });

    final response = await _http.send(request);
    if (response.statusCode != 200) {
      throw MiloException(
        _failureMessage(response.statusCode, await _readError(response)),
      );
    }

    await for (final event in decodeSseJson(response.stream)) {
      final text = _textOf(event);
      if (text.isNotEmpty) yield text;
    }
  }

  /// Pulls the text out of one streamed candidate. A chunk can carry
  /// several parts, and a safety-blocked chunk carries none.
  String _textOf(Map<String, dynamic> event) {
    final candidates = event['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final content = (candidates.first as Map<String, dynamic>)['content'];
    if (content is! Map<String, dynamic>) return '';
    final parts = content['parts'];
    if (parts is! List) return '';
    return parts
        .whereType<Map<String, dynamic>>()
        .map((part) => part['text'])
        .whereType<String>()
        .join();
  }

  Future<String?> _readError(http.StreamedResponse response) async {
    final body = await response.stream.bytesToString();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        if (message is String) return message;
      }
    } on FormatException {
      // Not JSON — fall through to the raw body.
    }
    return body.isEmpty ? null : body;
  }

  String _failureMessage(int status, String? detail) {
    switch (status) {
      case 400:
        // Gemini reports a malformed or unrecognised key as 400, not 401.
        return 'Gemini rejected the request${detail == null ? '' : ': $detail'}'
            '\nIf this is the first call, check the API key in Milo settings.';
      case 401:
      case 403:
        return 'Gemini rejected the API key. Check it in Milo settings.';
      case 429:
        return 'Gemini is rate limiting this key. Try again shortly.';
      case 404:
        return 'Gemini has no model called "$model".';
      default:
        return 'Gemini returned $status${detail == null ? '.' : ': $detail'}';
    }
  }
}
