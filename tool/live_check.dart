// One-off: drive the real GroqClient and GeminiClient against the live APIs.
//
// The unit tests fake the transport, which proves the framing but not that
// the model ids, headers and endpoints are right. This proves those.
//
//   dart run tool/live_check.dart
//
// Reads milo_keys.json, which is gitignored.

import 'dart:convert';
import 'dart:io';

import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/services/milo/gemini_client.dart';
import 'package:cotv/src/services/milo/groq_client.dart';
import 'package:http/http.dart' as http;

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

  stdout.writeln('=== Groq ($groqModelId) ===');
  await run(
    'groq  ',
    GroqClient(httpClient: client).streamReply(
      apiKey: keys['MILO_GROQ_API_KEY'] as String,
      systemPrompt: system,
      history: const [],
      prompt: prompt,
    ),
  );

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

  client.close();
}
