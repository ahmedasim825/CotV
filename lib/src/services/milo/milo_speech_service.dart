import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../../models/milo_models.dart';
import 'milo_credentials.dart';

/// Reads Milo's replies aloud.
///
/// Two implementations, picked by platform rather than configured, because
/// the right engine on each is not a preference: iOS has neural voices in
/// the OS and no way to run an ONNX synthesiser cheaply, and Windows has
/// SAPI voices that sound like a 2009 satnav and a Python process already
/// running beside the app.
abstract class MiloSpeechService {
  /// The voices this engine can actually speak with, best first.
  Future<List<MiloVoice>> voices();

  /// Chooses the voice for subsequent replies.
  Future<void> useVoice(MiloVoice voice);

  /// Speaks [text], interrupting anything already being said.
  ///
  /// Returns false when the engine refused. A missing or broken voice is
  /// not worth failing a turn over: the reply is already on screen, so the
  /// user loses the reading, not the answer.
  Future<bool> speak(String text);

  Future<void> stop();

  Future<void> dispose();

  /// Speaks a short line so a voice can be judged by ear rather than name.
  Future<void> preview(MiloVoice voice) async {
    await useVoice(voice);
    await speak('This is how I sound. Your next prayer is Asr, at 16:12.');
  }
}

/// The OS synthesiser, through `flutter_tts`.
///
/// On iOS this is `AVSpeechSynthesizer`, which is what puts Apple's neural
/// voices within reach — [preferredIosVoices] names the two worth having,
/// because nothing in the API distinguishes a neural voice from a compact
/// one except its name.
class SystemSpeechService implements MiloSpeechService {
  SystemSpeechService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  /// Slower than the platform default, which reads at a clip that suits a
  /// screen reader rather than a room. 0.5 is the documented "normal" on
  /// iOS; the Windows backend maps the same range onto SAPI.
  static const double speechRate = 0.5;

  final FlutterTts _tts;
  bool _configured = false;

  /// Whether a voice has been chosen for this session, by the user or by
  /// [_preferBestVoice]. Stops the automatic choice overriding a deliberate
  /// one on the next reply.
  bool _voiceChosen = false;

  @override
  Future<List<MiloVoice>> voices() async {
    try {
      await _configure();
      final raw = await _tts.getVoices;
      if (raw is! List) return const [];
      final seen = <String>{};
      final out = <MiloVoice>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final name = entry['name']?.toString();
        if (name == null || name.isEmpty || !seen.add(name)) continue;
        out.add(MiloVoice(name: name, locale: entry['locale']?.toString()));
      }
      // Apple's neural voices first, then English, then the rest: a German
      // voice reading English is unintelligible rather than merely
      // accented, and a compact voice is the thing users complain about.
      out.sort((a, b) {
        final byPreferred = a.preferenceRank.compareTo(b.preferenceRank);
        if (byPreferred != 0) return byPreferred;
        final aEn = a.isEnglish ? 0 : 1;
        final bEn = b.isEnglish ? 0 : 1;
        return aEn != bEn ? aEn - bEn : a.name.compareTo(b.name);
      });
      return out;
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> useVoice(MiloVoice voice) async {
    try {
      await _configure();
      await _tts.setVoice({
        'name': voice.name,
        if (voice.locale != null) 'locale': voice.locale!,
      });
      _voiceChosen = true;
    } on Object {
      // An uninstalled voice falls back to the platform default rather
      // than leaving Milo mute.
    }
  }

  @override
  Future<bool> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _configure();
      if (!_voiceChosen) await _preferBestVoice();
      await _tts.stop();
      await _tts.speak(trimmed);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // Nothing was speaking, or the engine is gone. Either way there is
      // nothing left to silence.
    }
  }

  @override
  Future<void> dispose() => stop();

  @override
  Future<void> preview(MiloVoice voice) async {
    await useVoice(voice);
    await speak('This is how I sound. Your next prayer is Asr, at 16:12.');
  }

  /// Picks Ava, then Zoe, then whatever sorts first — so the default on a
  /// fresh install is the good voice rather than the alphabetical one.
  ///
  /// Only ever runs when the user has not chosen, and only once: a stored
  /// choice is applied by the provider before the first reply, which sets
  /// [_voiceChosen] and takes this path out of play.
  Future<void> _preferBestVoice() async {
    _voiceChosen = true;
    final available = await voices();
    if (available.isEmpty) return;
    await useVoice(available.first);
  }

  Future<void> _configure() async {
    if (_configured) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(speechRate);
    await _tts.setVolume(1);
    await _tts.setPitch(1);
    _configured = true;
  }
}

/// Kokoro 82M, synthesised and played by the PC agent.
///
/// The audio is produced and played on the Windows machine rather than
/// streamed back to the app, which is both simpler and correct: on Windows
/// the app and the agent are the same machine, so returning a WAV over
/// loopback only to play it through the same speakers would add a decode
/// step and a dependency for nothing.
///
/// [fallback] takes over whenever the agent is not configured, not running,
/// or running without the model. That is not a nicety — this is the state
/// the machine is in until `kokoro-v1.0.onnx` has been fetched, and a Milo
/// that goes mute until then would look broken rather than unconfigured.
class KokoroSpeechService implements MiloSpeechService {
  KokoroSpeechService({
    required http.Client httpClient,
    required this.agent,
    required this.fallback,
    this.voiceId = kokoroVoiceId,
    this.timeout = speakTimeout,
  }) : _http = httpClient;

  static const String speakPath = '/speak';
  static const String stopPath = '/speak/stop';

  /// Synthesis is local and fast once the model is warm; the first line
  /// after the agent starts also loads it.
  static const Duration speakTimeout = Duration(seconds: 20);

  final http.Client _http;

  /// Resolved per call rather than held, because the address and token can
  /// change in the settings sheet while this service is alive.
  final Future<PcAgentConfig?> Function() agent;

  /// Speaks whenever the agent cannot.
  final MiloSpeechService fallback;

  final String voiceId;
  final Duration timeout;

  /// Set once the agent has answered a /speak, so a stop does not have to
  /// guess which engine is talking.
  bool _spokeLocally = false;

  @override
  Future<List<MiloVoice>> voices() async {
    final system = await fallback.voices();
    // Kokoro's profile is offered alongside the OS voices rather than
    // instead of them, so the picker still works when the agent is down.
    return [
      MiloVoice(name: voiceId, locale: 'en-US', isKokoro: true),
      ...system,
    ];
  }

  @override
  Future<void> useVoice(MiloVoice voice) async {
    if (voice.isKokoro) return;
    await fallback.useVoice(voice);
  }

  @override
  Future<bool> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    final config = await agent();
    if (config != null && await _post(config, trimmed)) {
      _spokeLocally = true;
      return true;
    }
    _spokeLocally = false;
    return fallback.speak(trimmed);
  }

  Future<bool> _post(PcAgentConfig agent, String text) async {
    try {
      final response = await _http
          .post(
            agent.endpoint(speakPath),
            headers: {
              'Authorization': 'Bearer ${agent.token}',
              'Content-Type': 'application/json',
              'User-Agent': miloUserAgent,
            },
            body: jsonEncode({'text': text, 'voice': voiceId}),
          )
          .timeout(timeout);
      return response.statusCode == 200;
    } on Object {
      // Unreachable, refused, or too slow. All three mean the same thing
      // here — the OS voice reads this line instead.
      return false;
    }
  }

  @override
  Future<void> stop() async {
    if (_spokeLocally) {
      final config = await agent();
      if (config != null) {
        try {
          await _http.post(
            config.endpoint(stopPath),
            headers: {'Authorization': 'Bearer ${config.token}'},
          ).timeout(timeout);
        } on Object {
          // The agent is gone, so whatever it was playing has stopped with
          // it. Nothing left to silence.
        }
      }
    }
    await fallback.stop();
  }

  @override
  Future<void> dispose() => stop();

  @override
  Future<void> preview(MiloVoice voice) async {
    await useVoice(voice);
    // Previewing the Kokoro profile has to go through this service; every
    // other voice belongs to the OS engine and is previewed by it.
    if (voice.isKokoro) {
      await speak('This is how I sound. Your next prayer is Asr, at 16:12.');
      return;
    }
    await fallback.preview(voice);
  }
}

/// One voice an engine can speak with.
class MiloVoice {
  const MiloVoice({required this.name, this.locale, this.isKokoro = false});

  final String name;
  final String? locale;

  /// Whether this is Kokoro's profile rather than an OS voice. The two are
  /// selected in completely different places, so the picker has to know
  /// which it is handing back.
  final bool isKokoro;

  bool get isEnglish => locale == null || locale!.toLowerCase().startsWith('en');

  /// 0 for Kokoro, then Apple's neural voices in [preferredIosVoices]
  /// order, then everything else.
  int get preferenceRank {
    if (isKokoro) return 0;
    final index = preferredIosVoices.indexWhere(
      (preferred) => name.toLowerCase().contains(preferred.toLowerCase()),
    );
    return index == -1 ? preferredIosVoices.length + 1 : index + 1;
  }

  /// "Microsoft Zira Desktop" reads better as "Zira (en-US)".
  String get label {
    if (isKokoro) return 'Kokoro $name  ·  local';
    final trimmed = name
        .replaceFirst(RegExp(r'^Microsoft\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+Desktop$', caseSensitive: false), '')
        .trim();
    final shown = trimmed.isEmpty ? name : trimmed;
    return locale == null ? shown : '$shown  ·  $locale';
  }
}
