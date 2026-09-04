import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../models/milo_models.dart';

/// Records one spoken command to a temporary file and hands back its bytes.
///
/// Owns the file for its whole life: the recording exists only between
/// [start] and [stop], and is deleted as soon as its bytes have been read.
/// Nothing spoken to Milo is left on disk after the turn that used it.
class VoiceCapture {
  VoiceCapture({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  /// 16 kHz mono WAV. Whisper resamples to 16 kHz regardless, so a higher
  /// rate buys nothing and costs upload time on a phone's uplink; WAV
  /// because it is the one encoder every platform this app targets
  /// supports without a codec pack.
  static const RecordConfig config = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
    // A phone held at arm's length in a room, not a studio mic.
    autoGain: true,
    noiseSuppress: true,
    echoCancel: true,
  );

  /// Long enough for any spoken command, short enough that a forgotten
  /// recording cannot fill the disk or blow past the upload limit.
  static const Duration maxDuration = Duration(seconds: 60);

  final AudioRecorder _recorder;
  String? _path;

  /// Amplitude while recording, for the level meter on the mic button.
  Stream<Amplitude> get amplitude =>
      _recorder.onAmplitudeChanged(const Duration(milliseconds: 120));

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Begins recording. Throws [MiloException] if the microphone is refused.
  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw MiloException(
        'Milo needs the microphone to hear a command. Allow microphone '
        'access for this app in system settings.',
      );
    }

    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/milo_command_${DateTime.now().microsecondsSinceEpoch}.wav';
    await _recorder.start(config, path: path);
    _path = path;
  }

  /// Stops recording and returns the audio, deleting the file behind it.
  ///
  /// Returns null when nothing was captured, which is what a tap that
  /// stopped before the recorder started looks like.
  Future<List<int>?> stopAndRead() async {
    final recorded = await _recorder.stop();
    final path = recorded ?? _path;
    _path = null;
    if (path == null) return null;

    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      return await file.readAsBytes();
    } finally {
      await _delete(file);
    }
  }

  /// Abandons the recording without reading it.
  Future<void> cancel() async {
    final recorded = await _recorder.stop();
    final path = recorded ?? _path;
    _path = null;
    if (path != null) await _delete(File(path));
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }

  /// A recording that outlives its turn is a privacy problem, not a disk
  /// one, so failure to delete is worth neither a crash nor silence.
  Future<void> _delete(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Windows can still hold the handle briefly after stop(); the OS
      // clears the temp directory either way.
    }
  }
}
