// One-off: drive the real OllamaClient and GeminiClient against the live
// runtimes.
//
// The unit tests fake the transport, which proves the framing but not that
// the model ids, headers and endpoints are right. This proves those.
//
//   dart run tool/live_check.dart
//
// Reads milo_keys.json, which is gitignored. The local half needs Ollama
// running with the model pulled; it reports that rather than failing if
// not, since the Gemini half is worth checking on its own.

import 'dart:convert';
import 'dart:io';

import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/services/milo/gemini_client.dart';
import 'package:cotv/src/services/milo/ollama_client.dart';
import 'package:cotv/src/services/milo/milo_tools.dart';
import 'package:http/http.dart' as http;

/// Stands in for the study layer, which needs a Riverpod container and a
/// Hive box that a command-line script has neither of. What is being proved
/// here is that the live model asks for the tool with usable arguments —
/// not what the app then does with them, which the unit tests cover.
class _StubStudy implements StudyToolTarget {
  final List<String> calls = [];

  @override
  Future<String> startTimer({
    required String subject,
    required int minutes,
  }) async {
    calls.add('start_study_timer(subject: $subject, minutes: $minutes)');
    return 'Started a $minutes-minute timer on $subject.';
  }

  @override
  Future<String> stopTimer() async {
    calls.add('stop_study_timer()');
    return 'Stopped the timer and logged 30 minutes.';
  }
}

Future<void> main() async {
  final keys = jsonDecode(File('milo_keys.json').readAsStringSync())
      as Map<String, dynamic>;
  final client = http.Client();

  const system = 'You are Milo. Answer in one short sentence.\n'
      'CONTEXT\nNext prayer: Asr at 16:12\nNow: 15:34';
  const prompt = 'When is Asr and how long do I have?';

  Future<void> run(String label, Stream<String> stream) async {
    final watch = Stopwatch()..start();
    final buffer = StringBuffer();
    Duration? firstToken;
    try {
      await for (final delta in stream) {
        firstToken ??= watch.elapsed;
        buffer.write(delta);
      }
      stdout.writeln('$label  OK');
      stdout.writeln('  first token : ${firstToken?.inMilliseconds}ms');
      stdout.writeln('  complete    : ${watch.elapsedMilliseconds}ms');
      stdout.writeln('  reply       : ${buffer.toString().trim()}');
    } on MiloException catch (error) {
      stdout.writeln('$label  FAILED');
      stdout.writeln('  ${error.message}');
    }
  }

  final ollama = OllamaClient(httpClient: client);
  final status = await ollama.probe();

  stdout.writeln('=== Local ($localModelId via $ollamaBaseUrl) ===');
  if (!status.isReady) {
    stdout.writeln('local   SKIPPED');
    stdout.writeln('  ${status.reason}');
    if (status.installed.isNotEmpty) {
      stdout.writeln('  installed   : ${status.installed.join(', ')}');
    }
  } else {
    await run(
      'local ',
      ollama.streamReply(
        systemPrompt: system,
        history: const [],
        prompt: prompt,
      ),
    );
  }

  stdout.writeln();
  stdout.writeln('=== Gemini ($geminiModelId) ===');
  await run(
    'gemini',
    GeminiClient(httpClient: client).streamReply(
      apiKey: keys['MILO_GEMINI_API_KEY'] as String,
      systemPrompt: system,
      history: const [],
      prompt: prompt,
    ),
  );

  stdout.writeln();
  if (status.isReady) {
    await _toolRoundTrip(client);
  } else {
    stdout.writeln('=== Local tool calling ===');
    stdout.writeln('tools   SKIPPED — ${status.reason}');
  }

  client.close();
}

/// Proves a tool call survives the round trip against the live API.
///
/// Three things can only be checked here: that this model id actually
/// supports tool calling, that the schema is accepted rather than rejected
/// as malformed, and that the arguments reassemble into the values the app
/// needs. The unit tests fake the frames, so they cannot tell a schema the
/// provider rejects from one it accepts.
Future<void> _toolRoundTrip(http.Client client) async {
  stdout.writeln('=== Local tool calling ($localModelId) ===');

  final study = _StubStudy();
  final tools = MiloTools(study);
  final ollama = OllamaClient(httpClient: client);

  const system = 'You are Milo, the assistant in a study app.\n'
      'CONTEXT\nSubjects: Physiology, Anatomy, Pharmacology\n'
      'Study timer: not running';
  const prompt = 'start a 45 minute physiology timer';

  final watch = Stopwatch()..start();
  final calls = <MiloToolCall>[];

  try {
    await for (final delta in ollama.streamTurn(
      systemPrompt: system,
      history: const [],
      prompt: prompt,
      tools: MiloTools.schemas,
    )) {
      if (delta is LocalToolCalls) calls.addAll(delta.calls);
    }

    if (calls.isEmpty) {
      stdout.writeln('tools   FAILED');
      stdout.writeln('  The model answered in prose instead of calling a '
          'tool. Check that $localModelId still supports tool calling.');
      return;
    }

    stdout.writeln('  asked for   : '
        '${calls.map((c) => '${c.name}(${jsonEncode(c.arguments)})').join(', ')}');

    final results = await tools.dispatchAll(calls);
    stdout.writeln('  dispatched  : ${study.calls.join(', ')}');

    final answer = StringBuffer();
    await for (final delta in ollama.streamTurn(
      systemPrompt: system,
      history: const [],
      prompt: prompt,
      exchange: MiloToolExchange(calls: calls, results: results),
    )) {
      if (delta is LocalText) answer.write(delta.text);
    }

    stdout.writeln('tools   OK');
    stdout.writeln('  complete    : ${watch.elapsedMilliseconds}ms');
    stdout.writeln('  reply       : ${answer.toString().trim()}');

    // The whole point of the tool: a subject and a duration pulled out of
    // prose. If either is wrong the round trip "worked" and the feature
    // did not.
    final start = calls.firstWhere(
      (call) => call.name == MiloTools.startStudyTimer,
      orElse: () => const MiloToolCall(id: '', name: '', arguments: {}),
    );
    final subject = start.stringArg('subject')?.toLowerCase();
    final minutes = start.intArg('minutes');
    if (subject != 'physiology' || minutes != 45) {
      stdout.writeln('  MISMATCH    : expected physiology/45, '
          'got $subject/$minutes');
    }
  } on MiloException catch (error) {
    stdout.writeln('tools   FAILED');
    stdout.writeln('  ${error.message}');
  }
}
