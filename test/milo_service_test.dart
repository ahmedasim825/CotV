// End-to-end turns through MiloService with the HTTP transport faked.
//
// The fake is at the socket, not at the client: OllamaClient, GeminiClient
// and PcRemoteService all run for real, so these tests cover the request
// bodies, the auth headers and the SSE parsing as well as the routing.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/models/pc_command.dart';
import 'package:cotv/src/services/milo/gemini_client.dart';
import 'package:cotv/src/services/milo/ollama_client.dart';
import 'package:cotv/src/services/milo/milo_credentials.dart';
import 'package:cotv/src/services/milo/milo_service.dart';
import 'package:cotv/src/services/milo/milo_tools.dart';
import 'package:cotv/src/services/milo/pc_remote_service.dart';

/// The app state every turn below is answered against.
final _context = MiloContext(
  now: DateTime(2026, 9, 2, 15, 34),
  nextPrayer: 'Asr',
  nextPrayerTime: DateTime(2026, 9, 2, 16, 12),
  isLockedOut: false,
  openTaskCount: 2,
  nextTaskTitles: const ['Anatomy revision', 'Pharmacology deck'],
);

const _secrets = MiloSecrets(
  geminiApiKey: 'gemini_test',
  pcHost: '192.168.1.20:8765',
  pcToken: 'agent_test',
);

/// One `text/event-stream` response, each frame delivered as its own chunk.
http.StreamedResponse _sse(List<String> frames) => http.StreamedResponse(
      Stream.fromIterable(frames.map(utf8.encode)),
      200,
      headers: const {'content-type': 'text/event-stream'},
    );

String _localFrame(String text) =>
    'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': text},
            },
          ],
        })}\n\n';

String _geminiFrame(String text) =>
    'data: ${jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': text},
                ],
              },
            },
          ],
        })}\n\n';

http.StreamedResponse _json(int status, Map<String, dynamic> body) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      status,
      headers: const {'content-type': 'application/json'},
    );

/// Records every request and answers each host from [onLocal], [onGemini]
/// and [onAgent].
class _Transport {
  _Transport({
    this.onLocal,
    this.onGemini,
    this.onAgent,
  });

  final Future<http.StreamedResponse> Function()? onLocal;
  final Future<http.StreamedResponse> Function()? onGemini;
  final Future<http.StreamedResponse> Function()? onAgent;

  final List<http.BaseRequest> requests = [];
  final Map<String, String> bodies = {};

  http.BaseRequest requestTo(String hostFragment) => requests
      .firstWhere((request) => request.url.toString().contains(hostFragment));

  Map<String, dynamic> bodyTo(String hostFragment) =>
      jsonDecode(bodies[requestTo(hostFragment).url.toString()]!)
          as Map<String, dynamic>;

  MockClient get client => MockClient.streaming((request, bodyStream) async {
        requests.add(request);
        bodies[request.url.toString()] = await bodyStream.bytesToString();

        final host = request.url.host;
        if (host.contains('googleapis')) return onGemini!();
        // Ollama and the PC agent are both plain IPs, so they are told
        // apart by path rather than by host.
        if (request.url.path.startsWith('/v1/') ||
            request.url.path.startsWith('/api/')) {
          return onLocal!();
        }
        return onAgent!();
      });
}

MiloService _serviceOn(
  http.Client client, {
  Duration? stall,
  MiloTools? tools,
}) =>
    MiloService(
      local: OllamaClient(
        httpClient: client,
        stallTimeout: stall ?? localStallTimeout,
      ),
      gemini: GeminiClient(
        httpClient: client,
        stallTimeout: stall ?? miloStallTimeout,
      ),
      pcRemote: PcRemoteService(httpClient: client),
      tools: tools,
      // Ollama is not running under test, and probing it would make every
      // local turn fall through to Gemini. Stated rather than discovered,
      // so a test that means to exercise the local engine does.
      localAvailability: () async => const LocalBrainStatus.ready(),
    );

/// Records what the study tools were asked to do.
class _RecordingStudy implements StudyToolTarget {
  final List<String> calls = [];

  @override
  Future<String> startTimer({
    required String subject,
    required int minutes,
  }) async {
    calls.add('start:$subject:$minutes');
    return 'Started a $minutes-minute timer on $subject.';
  }

  @override
  Future<String> stopTimer() async {
    calls.add('stop');
    return 'Stopped the timer and logged 30 minutes.';
  }
}

/// A `tool_calls` frame naming one function and its whole argument string.
String _localToolFrame(String id, String name, String arguments) =>
    'data: ${jsonEncode({
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': id,
                    'type': 'function',
                    'function': {'name': name, 'arguments': arguments},
                  },
                ],
              },
              'finish_reason': 'tool_calls',
            },
          ],
        })}\n\n';

Future<List<MiloEvent>> _run(
  MiloService service,
  String prompt, {
  MiloSecrets secrets = _secrets,
  List<ChatTurn> history = const [],
}) =>
    service
        .respond(
          rawPrompt: prompt,
          secrets: secrets,
          context: _context,
          history: history,
        )
        .toList();

String _textOf(List<MiloEvent> events) =>
    events.whereType<MiloTextDelta>().map((event) => event.text).join();

void main() {
  test('an everyday request stays on the local brain, with the app context '
      'attached', () async {
    final transport = _Transport(
      onLocal: () async => _sse([
        _localFrame('Asr is at 16:12'),
        _localFrame(', in 38 minutes.'),
        'data: [DONE]\n\n',
      ]),
    );

    final events = await _run(
      _serviceOn(transport.client),
      "Hey Milo, what's my next prayer?",
    );

    expect(events.whereType<MiloRouted>().single.decision.engine,
        MiloEngine.local);
    expect(_textOf(events), 'Asr is at 16:12, in 38 minutes.');
    expect(events.whereType<MiloPcExecuted>(), isEmpty);

    final body = transport.bodyTo('11434');
    expect(body['model'], localModelId);
    expect(body['stream'], isTrue);

    final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.first['role'], 'system');
    expect(messages.first['content'], contains('Next prayer: Asr at 16:12'));
    expect(messages.first['content'], contains('Anatomy revision'));
    // The wake word never reaches the model.
    expect(messages.last['content'], "what's my next prayer?");

    // Nothing authenticates to the local brain, and nothing should: a key
    // on this request would mean the prompt was going somewhere it needs
    // one.
    expect(
      transport.requestTo('11434').headers.containsKey('Authorization'),
      isFalse,
    );
    expect(transport.requestTo('11434').url.host, '127.0.0.1');
  });

  test('a synthesis request goes to Gemini, with the key off the URL',
      () async {
    final transport = _Transport(
      onGemini: () async => _sse([
        _geminiFrame('Start at 15:45'),
        _geminiFrame(' and stop for Asr.'),
      ]),
    );

    final events = await _run(
      _serviceOn(transport.client),
      'Plan a study block around Maghrib tonight',
    );

    expect(events.whereType<MiloRouted>().single.decision.engine,
        MiloEngine.gemini);
    expect(_textOf(events), 'Start at 15:45 and stop for Asr.');

    final request = transport.requestTo('googleapis');
    expect(request.url.path, contains('$geminiModelId:streamGenerateContent'));
    expect(request.url.queryParameters['alt'], 'sse');
    expect(request.headers['x-goog-api-key'], 'gemini_test');
    // A URL reaches proxy logs and crash reports; a header does not.
    expect(request.url.toString(), isNot(contains('gemini_test')));

    final body = transport.bodyTo('googleapis');
    final parts = (body['systemInstruction'] as Map)['parts'] as List;
    expect((parts.first as Map)['text'], contains('Next prayer: Asr'));
  });

  test('history is replayed with the role name each API expects', () async {
    final transport = _Transport(
      onGemini: () async => _sse([_geminiFrame('ok')]),
    );

    await _run(
      _serviceOn(transport.client),
      'Summarize that again',
      history: const [
        ChatTurn(role: MiloRole.user, text: 'first question'),
        ChatTurn(role: MiloRole.assistant, text: 'first answer'),
      ],
    );

    final contents =
        (transport.bodyTo('googleapis')['contents'] as List).cast<Map>();
    // Gemini calls the assistant side "model"; the app does not.
    expect(contents.map((entry) => entry['role']), ['user', 'model', 'user']);
  });

  test('a PC command runs on the agent, then the local brain reports the '
      'outcome',
      () async {
    final transport = _Transport(
      onLocal: () async => _sse([_localFrame('Spotify is up on your laptop.')]),
      onAgent: () async =>
          _json(200, {'ok': true, 'message': 'spotify is starting on your PC.'}),
    );

    final events = await _run(
      _serviceOn(transport.client),
      'Milo, open Spotify on my PC',
    );

    // The routing rail, the receipt, then the reply — in that order.
    expect(events.first, isA<MiloRouted>());
    expect(
      (events.first as MiloRouted).decision.engine,
      MiloEngine.local,
    );

    final receipt = events.whereType<MiloPcExecuted>().single.result;
    expect(receipt.ok, isTrue);
    expect(receipt.command.kind, PcActionKind.openApp);
    expect(receipt.message, 'spotify is starting on your PC.');
    expect(_textOf(events), 'Spotify is up on your laptop.');

    final agentRequest = transport.requestTo('192.168.1.20');
    expect(agentRequest.method, 'POST');
    expect(agentRequest.url.path, '/open-app');
    expect(agentRequest.headers['Authorization'], 'Bearer agent_test');
    expect(transport.bodyTo('192.168.1.20'), {'app': 'Spotify'});

    // The model is told what actually happened, so it cannot confirm an
    // action that did not run.
    final system =
        (transport.bodyTo('11434')['messages'] as List).first as Map;
    expect(system['content'], contains('PC ACTION'));
    expect(system['content'], contains('spotify is starting on your PC.'));
  });

  test('an unreachable agent fails the action but not the turn', () async {
    final transport = _Transport(
      onLocal: () async =>
          _sse([_localFrame('Your PC did not answer — is the agent running?')]),
      onAgent: () async => throw http.ClientException(
        'Connection refused',
        Uri.parse('http://192.168.1.20:8765/open-app'),
      ),
    );

    final events = await _run(
      _serviceOn(transport.client),
      'open Spotify on my pc',
    );

    final receipt = events.whereType<MiloPcExecuted>().single.result;
    expect(receipt.ok, isFalse);
    expect(receipt.message, contains('Connection refused'));
    // The reply still arrives, and it was told about the failure.
    expect(_textOf(events), isNotEmpty);
    expect(
      ((transport.bodyTo('11434')['messages'] as List).first as Map)['content'],
      contains('It failed'),
    );
  });

  test('an agent that refuses the target reports its own reason', () async {
    final transport = _Transport(
      onLocal: () async => _sse([_localFrame('Not in the allowlist.')]),
      onAgent: () async =>
          _json(404, {'detail': '"steam" is not in the agent\'s app list.'}),
    );

    final events = await _run(
      _serviceOn(transport.client),
      'open steam on the pc',
    );

    final receipt = events.whereType<MiloPcExecuted>().single.result;
    expect(receipt.ok, isFalse);
    expect(receipt.message, contains('not in the agent'));
  });

  test('a PC command with no agent configured says so instead of silently '
      'dropping', () async {
    final transport = _Transport(
      onLocal: () async => _sse([_localFrame('No agent configured.')]),
    );

    final events = await _run(
      _serviceOn(transport.client),
      'open Spotify on my pc',
      secrets: const MiloSecrets(geminiApiKey: 'gemini_test'),
    );

    final receipt = events.whereType<MiloPcExecuted>().single.result;
    expect(receipt.ok, isFalse);
    expect(receipt.message, contains('No PC agent is configured'));
  });

  test('a missing Gemini key names that engine', () async {
    final transport = _Transport(
      onGemini: () async => _sse([_geminiFrame('unreachable')]),
    );

    await expectLater(
      _run(
        _serviceOn(transport.client),
        'summarize my week',
        secrets: const MiloSecrets(),
      ),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('No Gemini API key'),
        ),
      ),
    );
    // Nothing was sent: the key is checked before the request is built.
    expect(transport.requests, isEmpty);
  });

  test('an un-pulled local model is reported with the command that fixes it',
      () async {
    final transport = _Transport(
      onLocal: () async => _json(404, {'error': 'model not found'}),
    );

    await expectLater(
      _run(_serviceOn(transport.client), 'when is Isha'),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('ollama pull $localModelId'),
        ),
      ),
    );
  });

  test('a local turn falls back to Gemini, and the rail says why', () async {
    final transport = _Transport(
      onGemini: () async => _sse([_geminiFrame('Isha is at 20:04.')]),
    );

    final service = MiloService(
      local: OllamaClient(httpClient: transport.client),
      gemini: GeminiClient(httpClient: transport.client),
      pcRemote: PcRemoteService(httpClient: transport.client),
      localAvailability: () async => const LocalBrainStatus.unreachable(),
    );

    final events = await _run(service, 'when is Isha');

    // One decision, not two: the availability check happens before the rail
    // is shown, so the badge never names an engine that did not run.
    final routed = events.whereType<MiloRouted>().single.decision;
    expect(routed.engine, MiloEngine.gemini);
    expect(routed.reason, contains('the local brain is not running'));
    expect(_textOf(events), 'Isha is at 20:04.');
    // Nothing was even attempted against Ollama.
    expect(
      transport.requests.where((r) => r.url.port == 11434),
      isEmpty,
    );
  });

  test('an unsupported platform routes to Gemini without probing', () async {
    final transport = _Transport(
      onGemini: () async => _sse([_geminiFrame('Asr is at 16:12.')]),
    );

    final service = MiloService(
      local: OllamaClient(httpClient: transport.client),
      gemini: GeminiClient(httpClient: transport.client),
      pcRemote: PcRemoteService(httpClient: transport.client),
      localAvailability: () async => const LocalBrainStatus.unsupported(),
    );

    final events = await _run(service, 'when is Isha');

    expect(
      events.whereType<MiloRouted>().single.decision.reason,
      contains('no local runtime'),
    );
  });

  test('a reply that produces no text is reported, not left blank', () async {
    final transport = _Transport(
      // Well-formed SSE, 200, and not one token of text: what Gemini 3
      // returns when the whole output budget went on internal reasoning.
      onGemini: () async => _sse([
        'data: {"candidates":[{"finishReason":"MAX_TOKENS"}]}\n\n',
      ]),
    );

    await expectLater(
      _run(_serviceOn(transport.client), 'summarize my week'),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          allOf(contains('Gemini Deep'), contains('returned no text')),
        ),
      ),
    );
  });

  test('a provider that stalls is abandoned rather than left hanging',
      () async {
    // A 200 whose body never produces a chunk: what an overloaded provider
    // looks like from the client side.
    final stalled = StreamController<List<int>>();
    addTearDown(stalled.close);
    final transport = _Transport(
      onLocal: () async => http.StreamedResponse(stalled.stream, 200,
          headers: const {'content-type': 'text/event-stream'}),
    );

    await expectLater(
      _run(
        _serviceOn(transport.client, stall: const Duration(milliseconds: 80)),
        'when is Isha',
      ),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('stopped responding'),
        ),
      ),
    );
  });

  test('a bare wake word is refused before anything is sent', () async {
    final transport = _Transport();

    await expectLater(
      _run(_serviceOn(transport.client), 'Hey Milo'),
      throwsA(isA<MiloException>()),
    );
    expect(transport.requests, isEmpty);
  });

  group('study tools', () {
    test('runs the tool, reports it, then answers with the result',
        () async {
      final study = _RecordingStudy();
      var call = 0;
      final transport = _Transport(
        onLocal: () async {
          call++;
          // First call asks for the tool; second answers with its result.
          return call == 1
              ? _sse([
                  _localToolFrame(
                    'call_a',
                    'start_study_timer',
                    '{"subject": "Physiology", "minutes": 45}',
                  ),
                  'data: [DONE]\n\n',
                ])
              : _sse([
                  _localFrame('Timer running on Physiology.'),
                  'data: [DONE]\n\n',
                ]);
        },
      );

      final events = await _run(
        _serviceOn(transport.client, tools: MiloTools(study)),
        'start a physiology timer for 45 minutes',
      );

      expect(study.calls, ['start:Physiology:45']);

      final receipt = events.whereType<MiloToolExecuted>().single;
      expect(receipt.summary, 'Started a 45-minute timer on Physiology.');

      final answer = events
          .whereType<MiloTextDelta>()
          .map((event) => event.text)
          .join();
      expect(answer, 'Timer running on Physiology.');

      // Two round trips: the ask, then the answer.
      expect(transport.requests, hasLength(2));
    });

    test('offers the tools on the first call and not on the second',
        () async {
      final study = _RecordingStudy();
      final bodies = <Map<String, dynamic>>[];
      var call = 0;
      final transport = _Transport(
        onLocal: () async {
          call++;
          return call == 1
              ? _sse([
                  _localToolFrame('call_a', 'stop_study_timer', '{}'),
                  'data: [DONE]\n\n',
                ])
              : _sse([_localFrame('Stopped.'), 'data: [DONE]\n\n']);
        },
      );

      await _run(
        _serviceOn(transport.client, tools: MiloTools(study)),
        'stop the timer',
      );

      for (final request in transport.requests) {
        bodies.add(
          jsonDecode(transport.bodies[request.url.toString()]!)
              as Map<String, dynamic>,
        );
      }

      // Both requests go to the same URL, so the recorded body is the last
      // one — the follow-up, which must carry no tools.
      expect(bodies.last.containsKey('tools'), isFalse);
      expect(study.calls, ['stop']);
    });

    test('no tools are offered when the service has none', () async {
      final transport = _Transport(
        onLocal: () async =>
            _sse([_localFrame('Asr is at 16:12.'), 'data: [DONE]\n\n']),
      );

      await _run(_serviceOn(transport.client), 'when is Asr');

      final body = transport.bodyTo('11434');
      expect(body.containsKey('tools'), isFalse);
    });

    test('a tool that ran is not treated as an empty reply', () async {
      // The action is its own answer: the receipt says what happened, so a
      // silent follow-up must not raise "returned no text".
      final study = _RecordingStudy();
      var call = 0;
      final transport = _Transport(
        onLocal: () async {
          call++;
          return call == 1
              ? _sse([
                  _localToolFrame(
                    'call_a',
                    'start_study_timer',
                    '{"subject": "Anatomy"}',
                  ),
                  'data: [DONE]\n\n',
                ])
              : _sse(['data: [DONE]\n\n']);
        },
      );

      // "start studying anatomy" rather than "start anatomy": the latter is
      // genuinely ambiguous with launching a PC app called Anatomy, and the
      // parser has no way to tell. Saying "studying" is what routes it here.
      final events = await _run(
        _serviceOn(transport.client, tools: MiloTools(study)),
        'start studying anatomy',
      );

      expect(study.calls, ['start:Anatomy:25']);
      expect(events.whereType<MiloToolExecuted>(), hasLength(1));
    });
  });
}
