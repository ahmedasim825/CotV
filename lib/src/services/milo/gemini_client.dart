import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/milo_models.dart';
import 'sse_stream.dart';

/// Streaming chat against the Gemini generative language API.
///
/// Carries the high-complexity half of Milo's routing: planning, summaries
/// and anything that has to hold several parts of the day in mind at once.
class GeminiClient {
  GeminiClient({
    required http.Client httpClient,
    this.model = geminiModelId,
    this.stallTimeout = miloStallTimeout,
  }) : _http = httpClient;

  static const String _apiRoot =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Gemini's ceiling for one reply.
  ///
  /// Higher than it looks like it needs to be. On Gemini 3 the model's
  /// internal reasoning is billed against this same budget — a trivial
  /// prompt measured 66 thinking tokens against 1 token of answer — so a
  /// ceiling sized for the visible reply alone returns an empty response
  /// with `finishReason: MAX_TOKENS` and no text at all.
  static const int maxOutputTokens = 4096;

  final http.Client _http;
  final String model;
  final Duration stallTimeout;

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
        'User-Agent': miloUserAgent,
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

    await for (final event in decodeSseJson(_bounded(response.stream))) {
      final text = _textOf(event);
      if (text.isNotEmpty) yield text;
    }
  }

  /// Fails the body stream if it goes quiet. This engine is the reason the
  /// timeout exists: it was measured at six minutes to first token while
  /// its capacity was short.
  Stream<List<int>> _bounded(Stream<List<int>> body) => body.timeout(
        stallTimeout,
        onTimeout: (sink) {
          sink.addError(
            MiloException(
              '${MiloEngine.gemini.badge} stopped responding after '
              '${stallTimeout.inSeconds}s. The provider is probably '
              'overloaded — try again, or rephrase so the instant engine '
              'can take it.',
            ),
          );
          sink.close();
        },
      );

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

  /// Where a working credential comes from, appended to auth failures.
  ///
  /// Deliberately says nothing about what a key *looks like*. An earlier
  /// version keyed off an "AIza" prefix and told the user their key was the
  /// wrong kind — which is the same failure as the 404 below blaming the
  /// model, just moved one step along: an assertion the code is in no
  /// position to make, stated with more confidence than the evidence.
  /// Google does not document a prefix, and a format can change without
  /// asking us.
  ///
  /// The server already says what it rejected, and [detail] carries that
  /// through. This only adds where to get another one.
  static const String _keySource =
      '\nGet a key at https://aistudio.google.com/apikey and paste it into '
      'Milo settings.';

  String _failureMessage(int status, String? detail) {
    switch (status) {
      case 400:
        // Gemini reports a malformed or unrecognised key as 400, not 401.
        return 'Gemini rejected the request'
            '${detail == null ? '' : ': $detail'}$_keySource';
      case 401:
      case 403:
        return 'Gemini rejected the credential'
            '${detail == null ? '.' : ': $detail'}$_keySource';
      case 429:
        return 'Gemini is rate limiting this key. Try again shortly.';
      case 404:
        // The server's own message is the useful part here and used to be
        // discarded: asked for a retired model it replies "no longer
        // available to new users. Please update your code to use
        // models/gemini-3.6-flash" — the answer, by name. Leading with it
        // beats any sentence this method could compose.
        //
        // Only when it says nothing does the ambiguity need spelling out:
        // a credential this endpoint cannot resolve also 404s, so a bare
        // 404 is not proof the model is the problem.
        return detail != null
            ? 'Gemini refused "$model": $detail'
            : 'Gemini returned 404 for "$model". Either that model id is '
                'retired, or the key was not accepted — this endpoint '
                'answers 404 for both.$_keySource';
      default:
        return 'Gemini returned $status${detail == null ? '.' : ': $detail'}';
    }
  }
}
