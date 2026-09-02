import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where to reach the Windows agent, and the token it will accept.
class PcAgentConfig {
  const PcAgentConfig({required this.baseUrl, required this.token});

  final Uri baseUrl;
  final String token;

  /// Parses what the user typed into the host field.
  ///
  /// A bare `192.168.1.20:8765` is accepted and assumed to be plain HTTP:
  /// the agent listens on the home Wi-Fi with no certificate, so requiring
  /// a scheme would only be a way to get the address wrong.
  static PcAgentConfig? parse(String? host, String? token) {
    if (host == null || token == null) return null;
    final trimmed = host.trim();
    if (trimmed.isEmpty || token.isEmpty) return null;

    final withScheme =
        trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) return null;

    return PcAgentConfig(baseUrl: uri, token: token);
  }

  Uri endpoint(String path) => baseUrl.replace(path: path);
}

/// The four secrets Milo needs, resolved from storage and the build.
class MiloSecrets {
  const MiloSecrets({
    this.groqApiKey,
    this.geminiApiKey,
    this.pcHost,
    this.pcToken,
  });

  final String? groqApiKey;
  final String? geminiApiKey;
  final String? pcHost;
  final String? pcToken;

  bool get hasGroq => groqApiKey != null;

  bool get hasGemini => geminiApiKey != null;

  /// Non-null only when both the host and the token are set, since either
  /// alone cannot make a call.
  PcAgentConfig? get pcAgent => PcAgentConfig.parse(pcHost, pcToken);
}

/// Reads and writes Milo's API keys and PC-agent credentials.
///
/// Values live in the iOS Keychain via `flutter_secure_storage`, and fall
/// back to compile-time `--dart-define`s when nothing has been entered on
/// the device. That split is deliberate: a development or CI build can
/// carry its keys in the build command, while a device build asks for them
/// once in Milo settings and never puts them in a file that could be
/// committed.
class MiloCredentials {
  MiloCredentials({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String groqKeyName = 'milo.groq_api_key';
  static const String geminiKeyName = 'milo.gemini_api_key';
  static const String pcHostName = 'milo.pc_host';
  static const String pcTokenName = 'milo.pc_token';

  static const String _envGroq = String.fromEnvironment('MILO_GROQ_API_KEY');
  static const String _envGemini =
      String.fromEnvironment('MILO_GEMINI_API_KEY');
  static const String _envPcHost = String.fromEnvironment('MILO_PC_HOST');
  static const String _envPcToken = String.fromEnvironment('MILO_PC_TOKEN');

  final FlutterSecureStorage _storage;

  Future<MiloSecrets> load() async {
    final stored = await Future.wait([
      _storage.read(key: groqKeyName),
      _storage.read(key: geminiKeyName),
      _storage.read(key: pcHostName),
      _storage.read(key: pcTokenName),
    ]);

    return MiloSecrets(
      groqApiKey: _resolve(stored[0], _envGroq),
      geminiApiKey: _resolve(stored[1], _envGemini),
      pcHost: _resolve(stored[2], _envPcHost),
      pcToken: _resolve(stored[3], _envPcToken),
    );
  }

  /// Writes every field it is given. A field left null is untouched; a
  /// field set to the empty string is deleted, which is how the settings
  /// sheet clears a key.
  Future<void> save({
    String? groqApiKey,
    String? geminiApiKey,
    String? pcHost,
    String? pcToken,
  }) async {
    await Future.wait([
      _write(groqKeyName, groqApiKey),
      _write(geminiKeyName, geminiApiKey),
      _write(pcHostName, pcHost),
      _write(pcTokenName, pcToken),
    ]);
  }

  Future<void> _write(String key, String? value) {
    if (value == null) return Future.value();
    final trimmed = value.trim();
    return trimmed.isEmpty
        ? _storage.delete(key: key)
        : _storage.write(key: key, value: trimmed);
  }

  /// Stored value wins over the build-time one, so entering a key on the
  /// device overrides whatever the build was compiled with.
  String? _resolve(String? stored, String fromEnvironment) {
    if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    if (fromEnvironment.trim().isNotEmpty) return fromEnvironment.trim();
    return null;
  }
}
