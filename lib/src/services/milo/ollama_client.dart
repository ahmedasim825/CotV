import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/milo_models.dart';
import 'sse_stream.dart';

/// One piece of a local turn.
///
/// A turn produces either prose or a request to call functions, and the
/// caller has to be able to tell them apart — a tool call is not text and
/// must never be rendered as an answer.
sealed class LocalDelta {
  const LocalDelta();
}

/// A chunk of reply text.
class LocalText extends LocalDelta {
  const LocalText(this.text);

  final String text;
}

/// Every tool call in the turn, reassembled and decoded.
///
/// Arrives once, at the end of the stream, because that is the first moment
/// the arguments are complete JSON.
class LocalToolCalls extends LocalDelta {
  const LocalToolCalls(this.calls);

  final List<MiloToolCall> calls;
}

/// Streaming chat against Ollama, on this machine.
///
/// Ollama exposes an OpenAI-compatible `/v1/chat/completions` alongside its
/// own `/api/chat`, and this uses the compatible one: same SSE framing and
/// the same `tool_calls` delta shape the cloud engines use, so the
/// reassembly below is the wire format Milo already knew rather than a
/// second one to keep working.
///
/// No key travels with these requests, because none exists — the whole
/// point of this engine is that the prompt does not leave the device.
class OllamaClient {
  /// [model] stays overridable so a machine with more memory can serve a
  /// larger Qwen without touching the routing code.
  OllamaClient({
    required http.Client httpClient,
    this.baseUrl = ollamaBaseUrl,
    this.model = localModelId,
    this.stallTimeout = localStallTimeout,
    this.probeTimeout = localProbeTimeout,
  }) : _http = httpClient;

  /// The local model's ceiling for one reply. Lower than the cloud
  /// engines': a 3B model asked for a long answer starts repeating itself
  /// well before it reaches a limit this size, so the ceiling is there to
  /// bound a loop rather than to leave room for one.
  static const int maxTokens = 700;

  final http.Client _http;
  final String baseUrl;
  final String model;
  final Duration stallTimeout;
  final Duration probeTimeout;

  Uri get _chatEndpoint => Uri.parse('$baseUrl/v1/chat/completions');

  Uri get _tagsEndpoint => Uri.parse('$baseUrl/api/tags');

  /// Whether Ollama is running here and [model] is pulled.
  ///
  /// Checked rather than assumed, and checked cheaply: routing a turn to an
  /// engine that is not installed would spend the user's patience on a
  /// connection refused. Returns a [LocalBrainStatus] rather than a bool so
  /// the three outcomes stay distinguishable — no Ollama, no model, ready —
  /// since the fix differs for each and only the app can say which it hit.
  Future<LocalBrainStatus> probe() async {
    final http.Response response;
    try {
      response = await _http.get(_tagsEndpoint).timeout(probeTimeout);
    } on Object {
      return const LocalBrainStatus.unreachable();
    }

    if (response.statusCode != 200) return const LocalBrainStatus.unreachable();

    final installed = _installedTags(response.body);
    // Ollama reports a pulled tag in full — `qwen2.5:3b-instruct` — but a
    // model pulled without one answers to `name` and reports `name:latest`,
    // so the bare name has to match too.
    final wanted = model.split(':').first;
    final has = installed.any(
      (tag) => tag == model || tag.split(':').first == wanted,
    );
    return has
        ? const LocalBrainStatus.ready()
        : LocalBrainStatus.modelMissing(installed);
  }

  List<String> _installedTags(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map || decoded['models'] is! List) return const [];
      return [
        for (final entry in decoded['models'] as List)
          if (entry is Map && entry['name'] is String) entry['name'] as String,
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Streams the reply to [prompt] as text only.
  ///
  /// The plain-prose path, kept for callers that offer no tools and have
  /// nothing to do with a tool call if one arrived.
  Stream<String> streamReply({
    required String systemPrompt,
    required List<ChatTurn> history,
    required String prompt,
  }) async* {
    await for (final delta in streamTurn(
      systemPrompt: systemPrompt,
      history: history,
      prompt: prompt,
    )) {
      if (delta is LocalText) yield delta.text;
    }
  }

  /// Streams one turn, which may produce text, tool calls, or both.
  ///
  /// [tools] is the JSON schema list sent as `tools`; omit it and the model
  /// is never offered any. [exchange] replays a previous round of calls and
  /// their results, which is what turns "the timer is started" into an
  /// answer that says so.
  Stream<LocalDelta> streamTurn({
    required String systemPrompt,
    required List<ChatTurn> history,
    required String prompt,
    List<Map<String, dynamic>>? tools,
    MiloToolExchange? exchange,
  }) async* {
    final request = http.Request('POST', _chatEndpoint)
      ..headers.addAll({
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

    final http.StreamedResponse response;
    try {
      response = await _http.send(request);
    } on Object catch (error) {
      // Connection refused is the ordinary case, not an exceptional one:
      // Ollama is a separate process the user can close.
      throw MiloException(_unreachableMessage(error));
    }

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
      if (content is String && content.isNotEmpty) yield LocalText(content);

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
      yield LocalToolCalls([
        for (final index in indexes) ?pending[index]!.toCall(),
      ]);
    }
  }

  /// Folds one frame's `tool_calls` array into [pending].
  ///
  /// Ollama omits `index` on models that emit a whole call in one frame,
  /// which the cloud engines never do. Falling back to the buffer count
  /// keeps those calls distinct instead of collapsing them onto index 0.
  void _accumulate(List<dynamic> calls, Map<int, _ToolCallBuffer> pending) {
    for (final raw in calls) {
      if (raw is! Map<String, dynamic>) continue;
      final rawIndex = raw['index'];
      final index = rawIndex is int ? rawIndex : pending.length;

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
      if (arguments is String) {
        buffer.arguments.write(arguments);
      } else if (arguments is Map) {
        // Ollama hands a complete call's arguments back as an object rather
        // than as a JSON string. Re-encoding keeps one decode path below.
        buffer.arguments.write(jsonEncode(arguments));
      }
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

  /// Fails the body stream if it goes quiet.
  ///
  /// Much tighter than the cloud engines' timeout, and for the opposite
  /// reason: there is no network between here and the model, so a local
  /// stall is a machine under load or a process that has wedged, not a
  /// provider working through a queue.
  Stream<List<int>> _bounded(Stream<List<int>> body) => body.timeout(
        stallTimeout,
        onTimeout: (sink) {
          sink.addError(
            MiloException(
              '${MiloEngine.local.badge} stopped responding after '
              '${stallTimeout.inSeconds}s. Ollama may be loading the model, '
              'or the machine may be out of memory.',
            ),
          );
          sink.close();
        },
      );

  Future<String?> _readError(http.StreamedResponse response) async {
    final body = await response.stream.bytesToString();
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        final error = decoded['error'];
        if (error is String) return error;
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
      }
    } on FormatException {
      // Not JSON. The body itself is the best detail available.
    }
    return body.isEmpty ? null : body;
  }

  String _unreachableMessage(Object error) =>
      'Ollama is not answering on $baseUrl. Start it, then pull the model '
      'with "ollama pull $model".';

  String _failureMessage(int status, String? detail) {
    switch (status) {
      case 404:
        return 'Ollama has no model called "$model". Pull it with '
            '"ollama pull $model".';
      case 500:
        return 'Ollama could not run "$model"${detail == null ? '.' : ': $detail'}'
            '\nA 3B model at Q4_K_M needs roughly 3GB free.';
      default:
        return 'Ollama returned $status${detail == null ? '.' : ': $detail'}';
    }
  }
}

/// Whether the local brain can take a turn, and why not when it cannot.
///
/// Three outcomes rather than a bool, because the fix differs for each and
/// the user is the only one who can apply it: start Ollama, pull the model,
/// or nothing.
class LocalBrainStatus {
  const LocalBrainStatus._(this.kind, this.installed);

  const LocalBrainStatus.ready() : this._(LocalBrainKind.ready, const []);

  const LocalBrainStatus.unreachable()
      : this._(LocalBrainKind.unreachable, const []);

  /// [installed] names what Ollama does have, so the message can say so
  /// instead of only naming what is missing.
  const LocalBrainStatus.modelMissing(List<String> installed)
      : this._(LocalBrainKind.modelMissing, installed);

  /// The platform has no local runtime at all — currently everything but
  /// Windows. Distinct from [LocalBrainStatus.unreachable], which is a
  /// runtime that exists and is not running.
  const LocalBrainStatus.unsupported()
      : this._(LocalBrainKind.unsupported, const []);

  final LocalBrainKind kind;

  /// Tags Ollama reports as pulled. Empty unless [kind] is
  /// [LocalBrainKind.modelMissing].
  final List<String> installed;

  bool get isReady => kind == LocalBrainKind.ready;

  /// Why the turn is going to Gemini instead, in one sentence. Null when
  /// the local brain is ready and nothing needs explaining.
  String? get reason {
    switch (kind) {
      case LocalBrainKind.ready:
        return null;
      case LocalBrainKind.unreachable:
        return 'the local brain is not running';
      case LocalBrainKind.modelMissing:
        return 'Ollama has not pulled $localModelId';
      case LocalBrainKind.unsupported:
        return 'this platform has no local runtime';
    }
  }
}

enum LocalBrainKind { ready, unreachable, modelMissing, unsupported }

/// How long a local reply may go without producing a byte.
const Duration localStallTimeout = Duration(seconds: 45);

/// How long to wait on the availability check.
///
/// Short by design: this runs before every turn that might go local, and a
/// slow answer here is indistinguishable from no answer for routing
/// purposes — either way the turn should already be on its way to Gemini.
const Duration localProbeTimeout = Duration(seconds: 2);

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
