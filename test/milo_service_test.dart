// End-to-end turns through MiloService with the HTTP transport faked.
//
// The fake is at the socket, not at the client: GroqClient, GeminiClient
// and PcRemoteService all run for real, so these tests cover the request
// bodies, the auth headers and the SSE parsing as well as the routing.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/models/pc_command.dart';
import 'package:cotv/src/services/milo/gemini_client.dart';
import 'package:cotv/src/services/milo/groq_client.dart';
import 'package:cotv/src/services/milo/milo_credentials.dart';
import 'package:cotv/src/services/milo/milo_service.dart';
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
  groqApiKey: 'gsk_test',
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

String _groqFrame(String text) =>
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

/// Records every request and answers each host from [onGroq], [onGemini]
/// and [onAgent].
class _Transport {
  _Transport({
    this.onGroq,
    this.onGemini,
    this.onAgent,
  });

  final Future<http.StreamedResponse> Function()? onGroq;
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
        if (host.contains('groq')) return onGroq!();
        if (host.contains('googleapis')) return onGemini!();
        return onAgent!();
      });
}

MiloService _serviceOn(http.Client client) => MiloService(
      groq: GroqClient(httpClient: client),
      gemini: GeminiClient(httpClient: client),
      pcRemote: PcRemoteService(httpClient: client),
    );

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
  test('an instant request goes to Groq with the app context attached',
      () async {
    final transport = _Transport(
      onGroq: () async => _sse([
        _groqFrame('Asr is at 16:12'),
        _groqFrame(', in 38 minutes.'),
        'data: [DONE]\n\n',
      ]),
    );

    final events = await _run(
      _serviceOn(transport.client),
      "Hey Milo, what's my next prayer?",
    );

    expect(events.whereType<MiloRouted>().single.decision.engine,
        MiloEngine.groq);
    expect(_textOf(events), 'Asr is at 16:12, in 38 minutes.');
    expect(events.whereType<MiloPcExecuted>(), isEmpty);

    final body = transport.bodyTo('groq');
    expect(body['model'], groqModelId);
    expect(body['stream'], isTrue);

    final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
    expect(messages.first['role'], 'system');
    expect(messages.first['content'], contains('Next prayer: Asr at 16:12'));
    expect(messages.first['content'], contains('Anatomy revision'));
    // The wake word never reaches the model.
    expect(messages.last['content'], "what's my next prayer?");

    expect(
      transport.requestTo('groq').headers['Authorization'],
      'Bearer gsk_test',
    );
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

  test('a PC command runs on the agent, then Groq reports the outcome',
      () async {
    final transport = _Transport(
      onGroq: () async => _sse([_groqFrame('Spotify is up on your laptop.')]),
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
      MiloEngine.groq,
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
    expect(transport.bodyTo('192.168.1.20'), {'app': 'spotify'});

    // The model is told what actually happened, so it cannot confirm an
    // action that did not run.
    final system =
        (transport.bodyTo('groq')['messages'] as List).first as Map;
    expect(system['content'], contains('PC ACTION'));
    expect(system['content'], contains('spotify is starting on your PC.'));
  });

  test('an unreachable agent fails the action but not the turn', () async {
    final transport = _Transport(
      onGroq: () async =>
          _sse([_groqFrame('Your PC did not answer — is the agent running?')]),
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
      ((transport.bodyTo('groq')['messages'] as List).first as Map)['content'],
      contains('It failed'),
    );
  });

  test('an agent that refuses the target reports its own reason', () async {
    final transport = _Transport(
      onGroq: () async => _sse([_groqFrame('Not in the allowlist.')]),
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
      onGroq: () async => _sse([_groqFrame('No agent configured.')]),
    );

    final events = await _run(
      _serviceOn(transport.client),
      'open Spotify on my pc',
      secrets: const MiloSecrets(groqApiKey: 'gsk_test'),
    );

    final receipt = events.whereType<MiloPcExecuted>().single.result;
    expect(receipt.ok, isFalse);
    expect(receipt.message, contains('No PC agent is configured'));
  });

  test('a missing key for the chosen engine names that engine', () async {
    final transport = _Transport(
      onGemini: () async => _sse([_geminiFrame('unreachable')]),
    );

    await expectLater(
      _run(
        _serviceOn(transport.client),
        'summarize my week',
        secrets: const MiloSecrets(groqApiKey: 'gsk_test'),
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

  test('a rejected key is reported as a key problem, not a raw status',
      () async {
    final transport = _Transport(
      onGroq: () async => _json(401, {
        'error': {'message': 'Invalid API Key'},
      }),
    );

    await expectLater(
      _run(_serviceOn(transport.client), 'when is Isha'),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('Groq rejected the API key'),
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
}
