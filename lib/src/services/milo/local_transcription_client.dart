import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/milo_models.dart';
import 'milo_credentials.dart';

/// Turns a recorded utterance into text using Faster-Whisper, running in
/// the PC agent on the Windows machine.
///
/// Preferred over the cloud transcriber whenever the agent is reachable,
/// and for one reason: the recording stays on a machine the user owns,
/// running a model they pulled, behind a token only they hold. It is not
/// the only path — [GroqTranscriptionClient] takes over when the agent is
/// not running, and is the only path on iOS, which has no agent — so
/// [MiloTranscriber] is what decides between them.
class LocalTranscriptionClient {
  LocalTranscriptionClient({
    required http.Client httpClient,
    this.model = localWhisperModelId,
    this.timeout = transcriptionTimeout,
  }) : _http = httpClient;

  /// The agent's path for this. Not modelled as a PC command, because
  /// nothing on the PC changes and the result is data rather than a receipt.
  static const String path = '/transcribe';

  /// A spoken command is short and the user is waiting. Roomier than the
  /// PC agent's command timeout because the first call after the agent
  /// starts also loads the model, which takes a few seconds on CPU.
  static const Duration transcriptionTimeout = Duration(seconds: 30);

  final http.Client _http;

  /// What the app would prefer. Sent nowhere: the agent chooses its own
  /// checkpoint, since it is the machine that has to hold it in memory, and
  /// reports back which one ran. Kept as a field so the constant has one
  /// home and the README has something to point at.
  final String model;

  final Duration timeout;

  /// Transcribes [bytes] on [agent].
  ///
  /// The WAV goes up as the raw request body rather than as a multipart
  /// upload. A FastAPI route declaring `UploadFile` raises at import time
  /// unless `python-multipart` is installed, so a multipart endpoint would
  /// have stopped the agent starting — and taken the PC commands down with
  /// it — on any machine that updated the agent without reinstalling its
  /// requirements.
  ///
  /// Returns the empty string when the recording held no speech — a tap that
  /// caught only silence is not an error, it just has nothing to send.
  Future<String> transcribe({
    required PcAgentConfig agent,
    required List<int> bytes,
  }) async {
    // Pinning the language stops Whisper hearing an accented English
    // command as another language and "translating" it into nonsense.
    final uri = agent
        .endpoint(path)
        .replace(queryParameters: const {'language': 'en'});

    final http.Response response;
    try {
      response = await _http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${agent.token}',
              'Content-Type': 'audio/wav',
              'User-Agent': miloUserAgent,
            },
            body: bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
          )
          .timeout(timeout);
    } on Exception catch (error) {
      throw MiloException(_transportMessage(error, agent));
    }

    final body = response.body;
    if (response.statusCode != 200) {
      throw MiloException(_failureMessage(response.statusCode, body));
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['text'] is! String) {
      throw MiloException(
        'The PC agent returned a transcription Milo could not read.',
      );
    }
    return (decoded['text'] as String).trim();
  }

  String _transportMessage(Object error, PcAgentConfig agent) {
    final text = error.toString();
    if (error is http.ClientException || text.contains('SocketException')) {
      return 'Could not reach the PC agent on ${agent.baseUrl.host} to '
          'transcribe. Speech runs on the PC now, so it needs the agent '
          'running.';
    }
    return 'Transcribing took longer than ${timeout.inSeconds}s. The first '
        'recording after the agent starts also loads the model — try again.';
  }

  String _failureMessage(int status, String body) {
    switch (status) {
      case 401:
      case 403:
        return 'The PC agent rejected the token. Check it matches the one in '
            'the agent config.';
      case 404:
        return 'This PC agent has no /transcribe endpoint. Update it from '
            'tools/milo_pc_agent and install faster-whisper.';
      case 503:
        return 'The PC agent is running without Faster-Whisper. Install it '
            'with "pip install -r tools/milo_pc_agent/requirements.txt".';
      default:
        String detail = body;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map) {
            final message = decoded['message'] ?? decoded['detail'];
            if (message is String) detail = message;
          }
        } on FormatException {
          // Not JSON; the raw body is the best detail available.
        }
        return 'The PC agent returned $status'
            '${detail.isEmpty ? '.' : ': $detail'}';
    }
  }
}
