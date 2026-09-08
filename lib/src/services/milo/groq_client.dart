import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/milo_models.dart';
import 'sse_stream.dart';

/// One piece of a Groq turn.
///
/// A turn produces either prose or a request to call functions, and the
/// caller has to be able to tell them apart — a tool call is not text and
/// must never be rendered as an answer.
sealed class GroqDelta {
  const GroqDelta();
}

/// A chunk of reply text.
class GroqText extends GroqDelta {
  const GroqText(this.text);

  final String text;
}

/// Every tool call in the turn, reassembled and decoded.
///
/// Arrives once, at the end of the stream, because that is the first moment
/// the arguments are complete JSON.
class GroqToolCalls extends GroqDelta {
  const GroqToolCalls(this.calls);

  final List<MiloToolCall> calls;
}

/// Streaming chat against Groq's OpenAI-compatible endpoint.
///
/// Carries the low-latency half of Milo's routing: short commands and
/// lookups, where the time to the first token is what the request is
/// being judged on.
class GroqClient {
  /// [model] stays overridable so a build can point at a larger Groq model
  /// without touching the routing code.
  GroqClient({
    required http.Client httpClient,
    this.model = groqModelId,
    this.stallTimeout = miloStallTimeout,
  }) : _http = httpClient;

  static final Uri endpoint =
      Uri.parse('https://api.groq.com/openai/v1/chat/completions');

  /// Groq's ceiling for one reply. Generous enough for a paragraph, low
  /// enough that a runaway generation cannot bill indefinitely.
  static const int maxTokens = 800;

  final http.Client _http;
  final String model;
  final Duration stallTimeout;

  /// Streams the reply to [prompt] as text only.
  ///
  /// The plain-prose path, kept for callers that offer no tools and have
  /// nothing to do with a tool call if one arrived.
  Stream<String> streamReply({
    required String apiKey,
    required String systemPrompt,
    required List<ChatTurn> history,
    required String prompt,
  }) async* {
    await for (final delta in streamTurn(
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      history: history,
      prompt: prompt,
    )) {
      if (delta is GroqText) yield delta.text;
    }
  }

  /// Streams one turn, which may produce text, tool calls, or both.
  ///
  /// [tools] is the JSON schema list sent as `tools`; omit it and the model
  /// is never offered any. [exchange] replays a previous round of calls and
  /// their results, which is what turns "the timer is started" into an
  /// answer that says so.
  Stream<GroqDelta> streamTurn({
    required String apiKey,
    required String systemPrompt,
    required List<ChatTurn> history,
    required String prompt,
    List<Map<String, dynamic>>? tools,
    MiloToolExchange? exchange,
  }) async* {
    final request = http.Request('POST', endpoint)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'User-Agent': miloUserAgent,
      })
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'max_tokens': maxTokens,
        if (tools != null && tools.isNotEmpty) ...{
          'tools': tools,
          'tool_choice': 'auto',
        },
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          for (final turn in history)
            {
              'role': turn.role == MiloRole.user ? 'user' : 'assistant',
              'content': turn.text,
            },
          {'role': 'user', 'content': prompt},
          if (exchange != null) ..._exchangeMessages(exchange),
        ],
      });

    final response = await _http.send(request);
    if (response.statusCode != 200) {
      throw MiloException(
        _failureMessage(response.statusCode, await _readError(response)),
      );
    }

    // Keyed by `tool_calls[i].index`, because a turn can carry more than
    // one call and their fragments interleave in the stream.
    final pending = <int, _ToolCallBuffer>{};

    await for (final event in decodeSseJson(_bounded(response.stream))) {
      final choices = event['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final choice = choices.first;
      if (choice is! Map<String, dynamic>) continue;

      final delta = choice['delta'];
      if (delta is! Map<String, dynamic>) continue;

      final content = delta['content'];
      if (content is String && content.isNotEmpty) yield GroqText(content);

      final calls = delta['tool_calls'];
      if (calls is List) _accumulate(calls, pending);
    }

    // Decoded here rather than on arrival. Arguments come through as JSON
    // fragments split across frames — `{"arguments":"{\"subject\":"}` then
    // `{"arguments":" \"physiology\"}"}` — so decoding each one throws
    // FormatException on every fragment but the last, which would surface
    // as a model fault rather than the parsing mistake it is. The end of
    // the stream is the first point the buffers are complete, and it is
    // reached whether the turn ended on `finish_reason: tool_calls` or the
    // body simply closed.
    if (pending.isNotEmpty) {
      final indexes = pending.keys.toList()..sort();
      yield GroqToolCalls([
        for (final index in indexes) ?pending[index]!.toCall(),
      ]);
    }
  }

  /// Folds one frame's `tool_calls` array into [pending].
  void _accumulate(List<dynamic> calls, Map<int, _ToolCallBuffer> pending) {
    for (final raw in calls) {
      if (raw is! Map<String, dynamic>) continue;
      final index = raw['index'];
      if (index is! int) continue;

      final buffer = pending.putIfAbsent(index, _ToolCallBuffer.new);

      // The id and the function name arrive only on the first fragment for
      // an index, so they are captured per index rather than re-read.
      final id = raw['id'];
      if (id is String && id.isNotEmpty) buffer.id = id;

      final function = raw['function'];
      if (function is! Map<String, dynamic>) continue;

      final name = function['name'];
      if (name is String && name.isNotEmpty) buffer.name = name;

      final arguments = function['arguments'];
      if (arguments is String) buffer.arguments.write(arguments);
    }
  }

  /// The assistant turn that asked for the calls, followed by one `tool`
  /// message per result.
  ///
  /// Every result carries the `tool_call_id` it answers: without it the
  /// model has no way to match a result to the call that produced it, and
  /// the API rejects the request outright.
  List<Map<String, dynamic>> _exchangeMessages(MiloToolExchange exchange) {
    return [
      {
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          for (final call in exchange.calls)
            {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': jsonEncode(call.arguments),
              },
            },
        ],
      },
      for (final call in exchange.calls)
        {
          'role': 'tool',
          'tool_call_id': call.id,
          'content': exchange.results[call.id] ?? 'No result.',
        },
    ];
  }

  /// Fails the body stream if it goes quiet, so an overloaded provider
  /// surfaces as a message instead of a panel that never finishes.
  Stream<List<int>> _bounded(Stream<List<int>> body) => body.timeout(
        stallTimeout,
        onTimeout: (sink) {
          sink.addError(
            MiloException(
              '${MiloEngine.groq.badge} stopped responding after '
              '${stallTimeout.inSeconds}s. The provider is probably '
              'overloaded — try again in a moment.',
            ),
          );
          sink.close();
        },
      );

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

/// One tool call as it accumulates across frames.
class _ToolCallBuffer {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();

  /// The finished call, or null if the stream never named a function —
  /// which leaves nothing to dispatch, so it is dropped rather than
  /// reported as a call to "".
  MiloToolCall? toCall() {
    final name = this.name;
    if (name == null) return null;

    return MiloToolCall(
      id: id ?? name,
      name: name,
      arguments: _decodeArguments(),
    );
  }

  /// The buffered JSON object.
  ///
  /// A tool that takes no parameters arrives with the arguments empty or
  /// as bare `{}`, so an empty buffer is an empty map, not a failure. A
  /// buffer that is neither is a genuinely malformed call, and an empty
  /// map is the safest reading: the dispatcher then reports the argument
  /// it needed as missing, rather than acting on half a value.
  Map<String, dynamic> _decodeArguments() {
    final raw = arguments.toString().trim();
    if (raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }
}
