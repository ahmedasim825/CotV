// The speech path: what goes on the wire to Whisper, and what comes back
// when it fails. The transport is faked, so GroqTranscriptionClient itself
// runs for real including its multipart encoding.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/services/milo/groq_transcription_client.dart';
import 'package:cotv/src/services/milo/milo_service.dart';
import 'package:cotv/src/services/milo/wake_word_listener.dart';

/// Records the one request the client sends.
class _Capture {
  http.BaseRequest? request;
  String? body;

  MockClient client(Future<http.StreamedResponse> Function() respond) =>
      MockClient.streaming((req, bodyStream) async {
        request = req;
        body = await bodyStream.bytesToString();
        return respond();
      });
}

http.StreamedResponse _json(int status, Object body) => http.StreamedResponse(
      Stream.value(utf8.encode(body is String ? body : jsonEncode(body))),
      status,
      headers: const {'content-type': 'application/json'},
    );

final _audio = List<int>.filled(2048, 7);

void main() {
  test('sends the audio as multipart with the model and language pinned',
      () async {
    final capture = _Capture();
    final client = GroqTranscriptionClient(
      httpClient: capture.client(
        () async => _json(200, {'text': '  Open Spotify on my PC.  '}),
      ),
    );

    final text = await client.transcribe(
      apiKey: 'gsk_test',
      bytes: _audio,
      filename: 'command.wav',
    );

    // Surrounding whitespace is Whisper's, not the user's.
    expect(text, 'Open Spotify on my PC.');

    final request = capture.request!;
    expect(request.method, 'POST');
    expect(request.url, GroqTranscriptionClient.endpoint);
    expect(request.headers['Authorization'], 'Bearer gsk_test');
    expect(request.headers['User-Agent'], miloUserAgent);
    expect(request.headers['content-type'], startsWith('multipart/form-data'));

    final body = capture.body!;
    expect(body, contains('name="model"'));
    expect(body, contains(whisperModelId));
    // Pinned so an accented command is transcribed, not translated.
    expect(body, contains('name="language"'));
    expect(body, contains('en'));
    // Whisper heard "Milo" as "Maido" and "Asr" as "ASR" without this.
    expect(body, contains('name="prompt"'));
    expect(body, contains('Milo'));
    expect(body, contains('Maghrib'));
    expect(body, contains('filename="command.wav"'));
    expect(body.codeUnits.length, greaterThan(_audio.length));
  });

  test('a rejected key is reported as a key problem', () async {
    final capture = _Capture();
    final client = GroqTranscriptionClient(
      httpClient: capture.client(
        () async => _json(401, {
          'error': {'message': 'Invalid API Key'},
        }),
      ),
    );

    await expectLater(
      client.transcribe(apiKey: 'bad', bytes: _audio),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('rejected the API key'),
        ),
      ),
    );
  });

  test('an oversized recording says so in terms the user can act on',
      () async {
    final capture = _Capture();
    final client = GroqTranscriptionClient(
      httpClient: capture.client(() async => _json(413, '')),
    );

    await expectLater(
      client.transcribe(apiKey: 'gsk_test', bytes: _audio),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          allOf(contains('too long'), contains('sentence or two')),
        ),
      ),
    );
  });

  test('an unreachable host is a connection problem, not a key problem',
      () async {
    final client = GroqTranscriptionClient(
      httpClient: MockClient.streaming((request, bodyStream) async {
        await bodyStream.bytesToString();
        throw http.ClientException('Connection refused', request.url);
      }),
    );

    await expectLater(
      client.transcribe(apiKey: 'gsk_test', bytes: _audio),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('Could not reach Groq'),
        ),
      ),
    );
  });

  test('a body that is not a transcription is refused rather than guessed',
      () async {
    final capture = _Capture();
    final client = GroqTranscriptionClient(
      httpClient: capture.client(() async => _json(200, {'unexpected': 1})),
    );

    await expectLater(
      client.transcribe(apiKey: 'gsk_test', bytes: _audio),
      throwsA(isA<MiloException>()),
    );
  });

  test('the wake word survives transcription for the service to strip',
      () async {
    // Whisper returns the wake word, and it must not reach the model. This
    // is the seam between the two: the transcript is passed through
    // untouched, and MiloService is what removes it.
    final capture = _Capture();
    final client = GroqTranscriptionClient(
      httpClient: capture.client(
        () async => _json(200, {'text': 'Hey Milo, open Spotify on my PC'}),
      ),
    );

    final text = await client.transcribe(apiKey: 'k', bytes: _audio);
    expect(text, 'Hey Milo, open Spotify on my PC');
    expect(MiloService.stripWakeWord(text), 'open Spotify on my PC');
  });

  group('wake-word capture', () {
    test('wraps captured PCM in a header the API can actually read', () {
      // A wrong header is the worst kind of bug here: the upload succeeds,
      // the transcript comes back empty, and nothing says why.
      final frames = [
        Uint8List.fromList(List<int>.filled(640, 1)),
        Uint8List.fromList(List<int>.filled(320, 2)),
      ];
      final wav = WakeWordListener.encodeWav(frames);
      final view = ByteData.view(wav.buffer);

      String tag(int at) =>
          String.fromCharCodes(wav.sublist(at, at + 4));

      expect(wav.length, 44 + 960);
      expect(tag(0), 'RIFF');
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(tag(36), 'data');
      expect(view.getUint32(4, Endian.little), 36 + 960);
      expect(view.getUint32(16, Endian.little), 16, reason: 'PCM chunk size');
      expect(view.getUint16(20, Endian.little), 1, reason: 'format is PCM');
      expect(view.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(view.getUint32(24, Endian.little), WakeWordListener.sampleRate);
      expect(view.getUint32(28, Endian.little),
          WakeWordListener.sampleRate * 2,
          reason: 'byte rate is rate x channels x bytes per sample');
      expect(view.getUint16(32, Endian.little), 2, reason: 'block align');
      expect(view.getUint16(34, Endian.little), 16, reason: 'bit depth');
      expect(view.getUint32(40, Endian.little), 960, reason: 'data length');

      // The samples survive the trip, in order.
      expect(wav[44], 1);
      expect(wav[44 + 640], 2);
    });

    test('an empty capture still produces a valid, empty file', () {
      final wav = WakeWordListener.encodeWav([]);
      expect(wav.length, 44);
      expect(ByteData.view(wav.buffer).getUint32(40, Endian.little), 0);
    });
  });
}
