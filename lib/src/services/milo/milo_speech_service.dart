import 'package:flutter_tts/flutter_tts.dart';

/// Reads Milo's replies aloud, using whatever voice the OS already has.
///
/// On-device rather than an API call: it starts speaking immediately with no
/// round trip, costs nothing per reply, and works with no network. Groq's
/// own speech models were the alternative and are not usable here — both
/// Orpheus voices answer `400 requires terms acceptance` on this account.
class MiloSpeechService {
  MiloSpeechService({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  /// Slower than the platform default, which reads at a clip that suits a
  /// screen reader rather than a room. 0.5 is the documented "normal" on
  /// iOS; the Windows backend maps the same range onto SAPI.
  static const double speechRate = 0.5;

  final FlutterTts _tts;
  bool _configured = false;

  /// The voices this platform can actually speak with.
  ///
  /// Read from the OS rather than hard-coded: Windows ships a handful and
  /// the user can install more from system settings, so a fixed list would
  /// go stale the moment they did.
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
      // English first: the app speaks English, and a German voice reading
      // it is unintelligible rather than merely accented.
      out.sort((a, b) {
        final aEn = a.isEnglish ? 0 : 1;
        final bEn = b.isEnglish ? 0 : 1;
        return aEn != bEn ? aEn - bEn : a.name.compareTo(b.name);
      });
      return out;
    } on Object {
      return const [];
    }
  }

  /// Chooses the voice for subsequent replies.
  Future<void> useVoice(MiloVoice voice) async {
    try {
      await _configure();
      await _tts.setVoice({
        'name': voice.name,
        if (voice.locale != null) 'locale': voice.locale!,
      });
    } on Object {
      // An uninstalled voice falls back to the platform default rather
      // than leaving Milo mute.
    }
  }

  /// Speaks [text], interrupting anything already being said.
  ///
  /// Returns false when the platform refused. A missing or broken voice is
  /// not worth failing a turn over: the reply is already on screen, so the
  /// user loses the reading, not the answer.
  Future<bool> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _configure();
      await _tts.stop();
      await _tts.speak(trimmed);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // Nothing was speaking, or the engine is gone. Either way there is
      // nothing left to silence.
    }
  }

  Future<void> dispose() => stop();

  /// Speaks a short line so a voice can be judged by ear rather than name.
  Future<void> preview(MiloVoice voice) async {
    await useVoice(voice);
    await speak('This is how I sound. Your next prayer is Asr, at 16:12.');
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

/// One voice the platform can speak with.
class MiloVoice {
  const MiloVoice({required this.name, this.locale});

  final String name;
  final String? locale;

  bool get isEnglish => locale == null || locale!.toLowerCase().startsWith('en');

  /// "Microsoft Zira Desktop" reads better as "Zira (en-US)".
  String get label {
    final trimmed = name
        .replaceFirst(RegExp(r'^Microsoft\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+Desktop$', caseSensitive: false), '')
        .trim();
    final shown = trimmed.isEmpty ? name : trimmed;
    return locale == null ? shown : '$shown  ·  $locale';
  }
}
