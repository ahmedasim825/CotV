// Tool calling: the SSE reassembly in OllamaClient, and the dispatch in
// MiloTools.
//
// The fake is at the socket, as in milo_service_test.dart, so the request
// bodies and the SSE parsing are covered as well as the accumulation.
//
// The framing here is the point. Arguments arrive as JSON fragments split
// across frames at arbitrary boundaries, and a turn can carry more than one
// call with their fragments interleaved. This mirrors the existing
// chunk-boundary test for plain text, which is where the same class of bug
// was caught before.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/services/milo/ollama_client.dart';
import 'package:cotv/src/services/milo/milo_tools.dart';

/// One `text/event-stream` response, each frame delivered as its own chunk.
http.StreamedResponse _sse(List<String> frames) => http.StreamedResponse(
      Stream.fromIterable(frames.map(utf8.encode)),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );

String _frame(Map<String, dynamic> delta, {String? finishReason}) =>
    'data: ${jsonEncode({
          'choices': [
            {'delta': delta, 'finish_reason': finishReason},
          ],
        })}\n\n';

/// A `tool_calls` delta for the call at [index].
String _toolFrame(
  int index, {
  String? id,
  String? name,
  String? arguments,
}) =>
    _frame({
      'tool_calls': [
        {
          'index': index,
          'id': ?id,
          'type': 'function',
          'function': {
            'name': ?name,
            'arguments': ?arguments,
          },
        },
      ],
    });

OllamaClient _clientReturning(
  List<String> frames, {
  List<http.Request>? capture,
}) {
  var call = 0;
  return OllamaClient(
    httpClient: MockClient.streaming((request, body) async {
      capture?.add(request as http.Request);
      call++;
      // The follow-up call carrying the tool results answers in prose.
      return call == 1
          ? _sse(frames)
          : _sse([
              _frame({'content': 'Started.'}),
              'data: [DONE]\n\n',
            ]);
    }),
  );
}

/// Records what the tools were asked to do.
class _RecordingStudy implements StudyToolTarget {
  final List<String> calls = [];
  String startResult = 'Started a 45-minute timer on Physiology.';
  String stopResult = 'Stopped the Physiology timer and logged 30 minutes.';

  @override
  Future<String> startTimer({
    required String subject,
    required int minutes,
  }) async {
    calls.add('start:$subject:$minutes');
    return startResult;
  }

  @override
  Future<String> stopTimer() async {
    calls.add('stop');
    return stopResult;
  }
}

Future<List<LocalDelta>> _drain(Stream<LocalDelta> stream) => stream.toList();

void main() {
  group('tool-call accumulation', () {
    test('reassembles arguments split mid-JSON across frames', () async {
      final client = _clientReturning([
        // The name and id arrive on the first fragment only.
        _toolFrame(0, id: 'call_a', name: 'start_study_timer', arguments: ''),
        _toolFrame(0, arguments: '{"subject":'),
        _toolFrame(0, arguments: ' "physiology"'),
        _toolFrame(0, arguments: ', "minutes": 45}'),
        _frame(const {}, finishReason: 'tool_calls'),
        'data: [DONE]\n\n',
      ]);

      final deltas = await _drain(client.streamTurn(
        systemPrompt: 'system',
        history: const [],
        prompt: 'start a physiology timer for 45 minutes',
        tools: MiloTools.schemas,
      ));

      final calls = deltas.whereType<LocalToolCalls>().single.calls;
      expect(calls, hasLength(1));
      expect(calls.single.id, 'call_a');
      expect(calls.single.name, 'start_study_timer');
      expect(calls.single.arguments,
          {'subject': 'physiology', 'minutes': 45});
    });

    test('keeps two interleaved calls apart by index', () async {
      final client = _clientReturning([
        _toolFrame(0, id: 'call_a', name: 'stop_study_timer', arguments: '{'),
        _toolFrame(1, id: 'call_b', name: 'start_study_timer', arguments: '{"sub'),
        _toolFrame(0, arguments: '}'),
        _toolFrame(1, arguments: 'ject": "Anatomy"}'),
        _frame(const {}, finishReason: 'tool_calls'),
        'data: [DONE]\n\n',
      ]);

      final deltas = await _drain(client.streamTurn(
        systemPrompt: 'system',
        history: const [],
        prompt: 'stop that and start anatomy',
        tools: MiloTools.schemas,
      ));

      final calls = deltas.whereType<LocalToolCalls>().single.calls;
      expect(calls, hasLength(2));

      // Ordered by index, not by arrival.
      expect(calls[0].name, 'stop_study_timer');
      expect(calls[0].arguments, isEmpty);
      expect(calls[1].name, 'start_study_timer');
      expect(calls[1].arguments, {'subject': 'Anatomy'});
    });

    test('a no-argument call arrives with an empty buffer, not a failure',
        () async {
      final client = _clientReturning([
        _toolFrame(0, id: 'call_a', name: 'stop_study_timer', arguments: ''),
        _frame(const {}, finishReason: 'tool_calls'),
        'data: [DONE]\n\n',
      ]);

      final calls = (await _drain(client.streamTurn(
        systemPrompt: 'system',
        history: const [],
        prompt: 'stop the timer',
        tools: MiloTools.schemas,
      )))
          .whereType<LocalToolCalls>()
          .single
          .calls;

      expect(calls.single.name, 'stop_study_timer');
      expect(calls.single.arguments, isEmpty);
    });

    test('reassembles even when the body closes without a finish reason',
        () async {
      // The stream simply ending is the other decode point, and a provider
      // that drops the trailing frame must not lose the call.
      final client = _clientReturning([
        _toolFrame(0, id: 'call_a', name: 'start_study_timer',
            arguments: '{"subject": "Anatomy"}'),
      ]);

      final calls = (await _drain(client.streamTurn(
        systemPrompt: 'system',
        history: const [],
        prompt: 'start anatomy',
        tools: MiloTools.schemas,
      )))
          .whereType<LocalToolCalls>()
          .single
          .calls;

      expect(calls.single.arguments, {'subject': 'Anatomy'});
    });

    test('text and tool calls both surface from one turn', () async {
      final client = _clientReturning([
        _frame({'content': 'On it. '}),
        _toolFrame(0, id: 'call_a', name: 'start_study_timer',
            arguments: '{"subject": "Anatomy"}'),
        _frame(const {}, finishReason: 'tool_calls'),
        'data: [DONE]\n\n',
      ]);

      final deltas = await _drain(client.streamTurn(
        systemPrompt: 'system',
        history: const [],
        prompt: 'start anatomy',
        tools: MiloTools.schemas,
      ));

      expect(deltas.whereType<LocalText>().single.text, 'On it. ');
      expect(deltas.whereType<LocalToolCalls>().single.calls, hasLength(1));
    });

    test('offers no tools when none are passed', () async {
      final requests = <http.Request>[];
      final client = _clientReturning([
        _frame({'content': 'Hello.'}),
        'data: [DONE]\n\n',
      ], capture: requests);

      await _drain(client.streamTurn(
        systemPrompt: 'system',
        history: const [],
        prompt: 'hello',
      ));

      final body = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(body.containsKey('tools'), isFalse);
      expect(body.containsKey('tool_choice'), isFalse);
    });
  });

  group('the tool result round trip', () {
    test('replays the assistant call and the result with a matching id',
        () async {
      final requests = <http.Request>[];
      final client = _clientReturning([
        _toolFrame(0, id: 'call_a', name: 'start_study_timer',
            arguments: '{"subject": "Anatomy"}'),
        'data: [DONE]\n\n',
      ], capture: requests);

      final calls = (await _drain(client.streamTurn(
        systemPrompt: 'system',
        history: const [],
        prompt: 'start anatomy',
        tools: MiloTools.schemas,
      )))
          .whereType<LocalToolCalls>()
          .single
          .calls;

      await _drain(client.streamTurn(
        systemPrompt: 'system',
        history: const [],
        prompt: 'start anatomy',
        exchange: MiloToolExchange(
          calls: calls,
          results: const {'call_a': 'Started a 25-minute timer on Anatomy.'},
        ),
      ));

      final body = jsonDecode(requests.last.body) as Map<String, dynamic>;
      final messages = body['messages'] as List<dynamic>;

      final assistant = messages[messages.length - 2] as Map<String, dynamic>;
      expect(assistant['role'], 'assistant');
      final toolCalls = assistant['tool_calls'] as List<dynamic>;
      expect((toolCalls.single as Map)['id'], 'call_a');

      final result = messages.last as Map<String, dynamic>;
      expect(result['role'], 'tool');
      expect(result['tool_call_id'], 'call_a');
      expect(result['content'], 'Started a 25-minute timer on Anatomy.');

      // The follow-up must not offer tools again, or the model can loop.
      expect(body.containsKey('tools'), isFalse);
    });
  });

  group('MiloTools dispatch', () {
    test('starts a timer with the arguments given', () async {
      final study = _RecordingStudy();
      final result = await MiloTools(study).dispatch(
        const MiloToolCall(
          id: 'call_a',
          name: 'start_study_timer',
          arguments: {'subject': 'Physiology', 'minutes': 45},
        ),
      );

      expect(study.calls, ['start:Physiology:45']);
      expect(result, study.startResult);
    });

    test('falls back to a Pomodoro when no duration was given', () async {
      final study = _RecordingStudy();
      await MiloTools(study).dispatch(
        const MiloToolCall(
          id: 'call_a',
          name: 'start_study_timer',
          arguments: {'subject': 'Physiology'},
        ),
      );

      expect(study.calls, ['start:Physiology:${MiloTools.defaultMinutes}']);
    });

    test('accepts a number-shaped string for minutes', () async {
      // Models emit "45" for an integer parameter often enough that
      // refusing it would be a self-inflicted failure.
      final study = _RecordingStudy();
      await MiloTools(study).dispatch(
        const MiloToolCall(
          id: 'call_a',
          name: 'start_study_timer',
          arguments: {'subject': 'Physiology', 'minutes': '45'},
        ),
      );

      expect(study.calls, ['start:Physiology:45']);
    });

    test('reports a missing subject instead of starting something', () async {
      final study = _RecordingStudy();
      final result = await MiloTools(study).dispatch(
        const MiloToolCall(
          id: 'call_a',
          name: 'start_study_timer',
          arguments: {'minutes': 45},
        ),
      );

      expect(study.calls, isEmpty);
      expect(result, contains('No subject'));
    });

    test('reports an unknown tool rather than throwing', () async {
      final study = _RecordingStudy();
      final result = await MiloTools(study).dispatch(
        const MiloToolCall(id: 'x', name: 'delete_everything', arguments: {}),
      );

      expect(study.calls, isEmpty);
      expect(result, contains('no tool called'));
    });

    test('runs several calls in order and keys them by id', () async {
      final study = _RecordingStudy();
      final results = await MiloTools(study).dispatchAll(const [
        MiloToolCall(id: 'a', name: 'stop_study_timer', arguments: {}),
        MiloToolCall(
          id: 'b',
          name: 'start_study_timer',
          arguments: {'subject': 'Anatomy'},
        ),
      ]);

      expect(study.calls, ['stop', 'start:Anatomy:25']);
      expect(results.keys, ['a', 'b']);
      expect(results['a'], study.stopResult);
    });
  });
}
