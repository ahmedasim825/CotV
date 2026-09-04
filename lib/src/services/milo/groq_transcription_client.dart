import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/milo_models.dart';

/// Turns a recorded utterance into text, using Groq's Whisper endpoint.
///
/// Speech goes through the same key as the instant engine, so voice needs no
/// second credential and no on-device model. It also means the request path
/// is one already proven to work: same host, same auth, same User-Agent
/// requirement.
class GroqTranscriptionClient {
  GroqTranscriptionClient({
    required http.Client httpClient,
    this.model = whisperModelId,
    this.timeout = transcriptionTimeout,
  }) : _http = httpClient;

  static final Uri endpoint =
      Uri.parse('https://api.groq.com/openai/v1/audio/transcriptions');

  /// A spoken command is short and the user is waiting, so this is much
  /// tighter than the chat stall timeout. Two utterances measured 1.1s and
  /// 1.7s end to end.
  static const Duration transcriptionTimeout = Duration(seconds: 30);

  /// Vocabulary hint sent with every recording.
  ///
  /// Whisper decodes toward words it expects, and none of these are in its
  /// everyday English: "Milo" came back as "Maido" and "Asr" as "ASR". The
  /// API takes this as a stylistic prior rather than a constraint, so it
  /// biases those spellings without preventing anything else being heard.
  ///
  /// Kept to names the decoder cannot guess. Padding it with ordinary words
  /// would dilute the bias on the ones that need it.
  static const String vocabularyHint =
      'Milo. Fajr, Dhuhr, Asr, Maghrib, Isha, adhan, qibla. '
      'Spotify, Chrome, Discord, VS Code, Notepad, Explorer.';

  final http.Client _http;
  final String model;
  final Duration timeout;

  /// Transcribes [bytes], recorded as [filename].
  ///
  /// Returns the empty string when the recording held no speech — a tap that
  /// caught only silence is not an error, it just has nothing to send.
  Future<String> transcribe({
    required String apiKey,
    required List<int> bytes,
    String filename = 'command.wav',
  }) async {
    final request = http.MultipartRequest('POST', endpoint)
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'User-Agent': miloUserAgent,
      })
      ..fields['model'] = model
      ..fields['response_format'] = 'json'
      // Pinning the language stops Whisper hearing an accented English
      // command as another language and "translating" it into nonsense.
      ..fields['language'] = 'en'
      ..fields['prompt'] = vocabularyHint
      ..files.add(http.MultipartFile.fromBytes('file', bytes,
          filename: filename));

    final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(timeout);
    } on Exception catch (error) {
      throw MiloException(_transportMessage(error));
    }

    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      throw MiloException(_failureMessage(response.statusCode, body));
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['text'] is! String) {
      throw MiloException('Groq returned a transcription Milo could not read.');
    }
    return (decoded['text'] as String).trim();
  }

  String _transportMessage(Object error) {
    final text = error.toString();
    if (error is http.ClientException || text.contains('SocketException')) {
      return 'Could not reach Groq to transcribe. Check the connection.';
    }
    return 'Transcribing took longer than ${timeout.inSeconds}s. Try a '
        'shorter recording.';
  }

  String _failureMessage(int status, String body) {
    switch (status) {
      case 401:
      case 403:
        return 'Groq rejected the API key. Check it in Milo settings.';
      case 413:
        return 'That recording is too long for Groq to accept. Keep a '
            'spoken command to a sentence or two.';
      case 429:
        return 'Groq is rate limiting this key. Try again shortly.';
      case 404:
        return 'Groq has no speech model called "$model".';
      default:
        String detail = body;
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map && decoded['error'] is Map) {
            final message = (decoded['error'] as Map)['message'];
            if (message is String) detail = message;
          }
        } on FormatException {
          // Not JSON; the raw body is the best detail available.
        }
        return 'Groq returned $status${detail.isEmpty ? '.' : ': $detail'}';
    }
  }
}
