// The speech path: what goes on the wire to the PC agent's Faster-Whisper,
// and what comes back when it fails. The transport is faked, so
// LocalTranscriptionClient itself runs for real including its multipart
// encoding.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/services/milo/local_transcription_client.dart';
import 'package:cotv/src/services/milo/milo_credentials.dart';
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

final _agent = PcAgentConfig.parse('192.168.1.20:8765', 'agent_test')!;

void main() {
  test('sends the audio as a raw body with the language pinned', () async {
    final capture = _Capture();
    final client = LocalTranscriptionClient(
      httpClient: capture.client(
        () async => _json(200, {'text': '  Open Spotify on my PC.  '}),
      ),
    );

    final text = await client.transcribe(agent: _agent, bytes: _audio);

    // Surrounding whitespace is Whisper's, not the user's.
    expect(text, 'Open Spotify on my PC.');

    final request = capture.request!;
    expect(request.method, 'POST');
    expect(request.url.path, LocalTranscriptionClient.path);
    expect(request.headers['Authorization'], 'Bearer agent_test');
    expect(request.headers['User-Agent'], miloUserAgent);

    // Raw bytes, not multipart. A FastAPI route declaring UploadFile raises
    // at import time without python-multipart, which would stop the agent
    // starting and take the PC commands with it — so the wire format here
    // is load-bearing, not a preference.
    expect(request.headers['content-type'], 'audio/wav');
    expect(capture.body!.codeUnits, hasLength(_audio.length));

    // Pinned so an accented command is transcribed, not translated.
    expect(request.url.queryParameters['language'], 'en');
  });

  test('a rejected token is reported as a token problem', () async {
    final capture = _Capture();
    final client = LocalTranscriptionClient(
      httpClient: capture.client(
        () async => _json(401, {'detail': 'Bad or missing token.'}),
      ),
    );

    await expectLater(
      client.transcribe(agent: _agent, bytes: _audio),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('rejected the token'),
        ),
      ),
    );
  });

  test('an agent without Faster-Whisper says how to install it', () async {
    final capture = _Capture();
    final client = LocalTranscriptionClient(
      httpClient: capture.client(
        () async => _json(503, {'detail': 'faster-whisper is not installed.'}),
      ),
    );

    await expectLater(
      client.transcribe(agent: _agent, bytes: _audio),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('requirements.txt'),
        ),
      ),
    );
  });

  test('an older agent with no /transcribe says to update it', () async {
    final capture = _Capture();
    final client = LocalTranscriptionClient(
      httpClient: capture.client(() async => _json(404, '')),
    );

    await expectLater(
      client.transcribe(agent: _agent, bytes: _audio),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('no /transcribe endpoint'),
        ),
      ),
    );
  });

  test('an unreachable host is a connection problem, not a key problem',
      () async {
    final client = LocalTranscriptionClient(
      httpClient: MockClient.streaming((request, bodyStream) async {
        await bodyStream.bytesToString();
        throw http.ClientException('Connection refused', request.url);
      }),
    );

    await expectLater(
      client.transcribe(agent: _agent, bytes: _audio),
      throwsA(
        isA<MiloException>().having(
          (error) => error.message,
          'message',
          contains('Could not reach the PC agent'),
        ),
      ),
    );
  });

  test('a body that is not a transcription is refused rather than guessed',
      () async {
    final capture = _Capture();
    final client = LocalTranscriptionClient(
      httpClient: capture.client(() async => _json(200, {'unexpected': 1})),
    );

    await expectLater(
      client.transcribe(agent: _agent, bytes: _audio),
      throwsA(isA<MiloException>()),
    );
  });

  test('the wake word survives transcription for the service to strip',
      () async {
    // Whisper returns the wake word, and it must not reach the model. This
    // is the seam between the two: the transcript is passed through
    // untouched, and MiloService is what removes it.
    final capture = _Capture();
    final client = LocalTranscriptionClient(
      httpClient: capture.client(
        () async => _json(200, {'text': 'Hey Milo, open Spotify on my PC'}),
      ),
    );

    final text = await client.transcribe(agent: _agent, bytes: _audio);
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

  group('clap to wake', () {
    // 20ms of 16kHz mono 16-bit audio, which is the frame size the recorder
    // actually delivers. Only the byte count matters here — the detector
    // works on levels, not samples.
    const frame = 640;

    /// Feeds [levels] one frame at a time and returns the indexes that
    /// fired, so a test can assert *when* as well as whether.
    List<int> fire(ClapDetector detector, List<double> levels) => [
          for (var i = 0; i < levels.length; i++)
            if (detector.accept(levels[i], frame)) i,
        ];

    /// A quiet room, then a spike, then quiet again.
    List<double> clapAfter(double quiet, double peak, {int lead = 40}) => [
          ...List<double>.filled(lead, quiet),
          peak,
          quiet,
          quiet,
          quiet,
        ];

    test('a spike that decays fires, one frame after the peak', () {
      final detector = ClapDetector();
      final fired = fire(detector, clapAfter(0.01, 0.5));

      // Not on the peak itself: the shape is not knowable until it falls.
      expect(fired, [41]);
    });

    test('speech does not fire, however loud it gets', () {
      final detector = ClapDetector();
      // A syllable ramps up and holds, which is the whole difference.
      final speech = [
        ...List<double>.filled(40, 0.01),
        0.04, 0.09, 0.16, 0.24, 0.30, 0.32, 0.31, 0.28, 0.24, 0.18,
        0.12, 0.06, 0.02,
      ];

      expect(fire(detector, speech), isEmpty);
    });

    test('a sustained loud noise does not fire', () {
      final detector = ClapDetector();
      // A door slamming into a held rumble, or music starting.
      final sustained = [
        ...List<double>.filled(40, 0.01),
        ...List<double>.filled(30, 0.55),
      ];

      expect(fire(detector, sustained), isEmpty);
    });

    test('a quiet tap in a silent room does not fire', () {
      final detector = ClapDetector();
      // Clears the rise ratio against near-silence but not the absolute
      // floor, which is what that second test is for.
      expect(fire(detector, clapAfter(0.001, 0.05)), isEmpty);
    });

    test('the echo of a clap does not open a second capture', () {
      final detector = ClapDetector();
      final levels = [
        ...List<double>.filled(40, 0.01),
        0.6, 0.05, // the clap
        0.35, 0.04, // its reflection off the far wall
        0.30, 0.03,
      ];

      expect(fire(detector, levels), hasLength(1));
    });

    test('a noisy room raises the bar rather than firing constantly', () {
      final detector = ClapDetector();
      // A fan: loud enough to clear the absolute floor on its own, and
      // steady, so nothing about it is a step change.
      final fan = List<double>.filled(200, 0.2);

      expect(fire(detector, fan), isEmpty);
      expect(detector.idleFloor, greaterThan(0.15));
    });

    test('reset returns it to a silent room', () {
      final detector = ClapDetector();
      fire(detector, List<double>.filled(200, 0.2));
      detector.reset();

      expect(detector.idleFloor, 0.01);
      expect(fire(detector, clapAfter(0.01, 0.5)), isNotEmpty);
    });
  });
}
