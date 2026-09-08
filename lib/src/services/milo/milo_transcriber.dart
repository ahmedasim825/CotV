import '../../models/milo_models.dart';
import 'groq_transcription_client.dart';
import 'local_transcription_client.dart';
import 'milo_credentials.dart';

/// Decides which Whisper hears a recording.
///
/// Two transcribers, and the choice between them is not a preference: the
/// local one keeps the audio on a machine the user owns, and the cloud one
/// is the only path that exists on iOS, which has no PC agent. So the rule
/// is "local when it is actually running, Groq otherwise" — the private
/// option when it is there, a working option always.
///
/// The agent is tried rather than checked. A reachability probe before
/// every recording would add a round trip to the path the user is waiting
/// on, and it would still be a guess by the time the real request went out.
class MiloTranscriber {
  const MiloTranscriber({required this.local, required this.groq});

  final LocalTranscriptionClient local;
  final GroqTranscriptionClient groq;

  /// Transcribes [bytes], preferring [agent] when one is configured.
  ///
  /// Throws [MiloException] when neither path is available, naming both —
  /// the fix is either starting the agent or adding a key, and the user is
  /// the only one who knows which they meant to have.
  Future<String> transcribe({
    required List<int> bytes,
    PcAgentConfig? agent,
    String? groqApiKey,
  }) async {
    if (agent != null) {
      try {
        return await local.transcribe(agent: agent, bytes: bytes);
      } on MiloException {
        // The agent is configured but not answering, or is running without
        // Faster-Whisper. Fall through rather than fail: a configured agent
        // that happens to be asleep should not cost the user their voice
        // input when a key is sitting right there.
        if (groqApiKey == null) rethrow;
      }
    }

    if (groqApiKey == null) {
      throw MiloException(
        'Speech needs somewhere to run. Either start the Milo agent on your '
        'PC to transcribe locally, or add a Groq key in Milo settings.',
      );
    }

    return groq.transcribe(apiKey: groqApiKey, bytes: bytes);
  }
}
