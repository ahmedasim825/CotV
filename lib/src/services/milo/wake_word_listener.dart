import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Listens for "Hey Milo" — or a clap — on device, then captures the
/// command that follows.
///
/// The wake word is spotted by a sherpa-onnx zipformer keyword model running
/// locally, not by uploading audio and reading the transcript. That is the
/// whole point: **nothing leaves the machine until the phrase actually
/// matches.** Ambient conversation is decoded on device and discarded.
///
/// Keywords are BPE token sequences rather than a trained model, so adding a
/// phrase is a line in `assets/kws/keywords.txt` and needs no training run.
///
/// A clap opens the same capture, and is detected by shape rather than by a
/// model: see [ClapDetector]. It exists for the case the wake word is worst
/// at — hands wet, mouth full, across a room — and costs nothing when
/// unused, because the arithmetic runs on frames the spotter is already
/// being fed.
///
/// One microphone stream serves both jobs. While idle every frame goes to
/// the spotter; once either trigger fires, frames are buffered instead until
/// the speaker stops, and that buffer — only that buffer — is handed back to
/// be transcribed.
class WakeWordListener {
  WakeWordListener({AudioRecorder? recorder, this.clapToWake = true})
      : _recorder = recorder ?? AudioRecorder();

  /// Whether a clap also opens a capture.
  final bool clapToWake;

  static const RecordConfig config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    sampleRate: sampleRate,
    numChannels: 1,
    autoGain: true,
    noiseSuppress: true,
    echoCancel: true,
  );

  static const int sampleRate = 16000;
  static const int _bytesPerSample = 2;

  static const String _assetDir = 'assets/kws';
  static const List<String> _assetFiles = [
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'joiner.int8.onnx',
    'tokens.txt',
    'keywords.txt',
  ];

  /// How long the speaker must stop before the command is considered
  /// finished. Long enough to survive the pause in "Milo… open Spotify".
  static const Duration trailingSilence = Duration(milliseconds: 900);

  /// A command is cut off here, so a conversation that happens to start
  /// with the wake word cannot be uploaded in full.
  static const Duration maxCommand = Duration(seconds: 9);

  /// If the wake word fires and nothing follows, give up rather than
  /// holding the buffer open.
  static const Duration commandGracePeriod = Duration(seconds: 3);

  final AudioRecorder _recorder;

  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _kwsStream;
  StreamSubscription<Uint8List>? _frames;
  StreamController<Uint8List>? _commands;

  /// Diagnostics. Without these a failure anywhere in the chain — no
  /// frames, unreadable frames, frames the spotter never fires on — looks
  /// identical from the outside: nothing happens.
  int framesSeen = 0;
  int samplesSeen = 0;
  double peakLevel = 0;
  int detections = 0;

  /// Captures opened by a clap rather than by the wake word. Counted
  /// separately because the two fail differently: a spotter that never
  /// fires is a model problem, and a clap detector that never fires is a
  /// threshold problem.
  int clapDetections = 0;
  String? lastError;

  bool _capturing = false;
  final List<Uint8List> _captured = [];
  int _capturedBytes = 0;
  int _silentBytes = 0;
  int _sinceWakeBytes = 0;
  bool _heardAnything = false;
  double _noiseFloor = 0.01;

  /// Judges claps against the idle room, separately from [_noiseFloor] —
  /// that one only moves during a capture, and a clap has to be measured
  /// against the room as it was before anything happened.
  final ClapDetector _clap = ClapDetector();

  bool get isListening => _frames != null;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Starts listening. Each command spoken after the wake word arrives as a
  /// WAV, ready to transcribe.
  Future<Stream<Uint8List>> start() async {
    await stop();

    final spotter = await _loadSpotter();
    final frames = await _recorder.startStream(config);

    _spotter = spotter;
    _kwsStream = spotter.createStream();
    framesSeen = 0;
    samplesSeen = 0;
    peakLevel = 0;
    detections = 0;
    clapDetections = 0;
    lastError = null;
    _clap.reset();
    final commands = StreamController<Uint8List>();
    _commands = commands;
    _resetCapture();

    _frames = frames.listen(
      _onFrame,
      onError: commands.addError,
      onDone: commands.close,
      cancelOnError: false,
    );

    return commands.stream;
  }

  Future<void> stop() async {
    await _frames?.cancel();
    _frames = null;
    if (_commands != null) await _recorder.stop();
    await _commands?.close();
    _commands = null;

    _kwsStream?.free();
    _kwsStream = null;
    _spotter?.free();
    _spotter = null;
    _resetCapture();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }

  Future<sherpa.KeywordSpotter> _loadSpotter() async {
    sherpa.initBindings();
    final dir = await _materialiseModel();

    return sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: '$dir/encoder.int8.onnx',
            decoder: '$dir/decoder.int8.onnx',
            joiner: '$dir/joiner.int8.onnx',
          ),
          tokens: '$dir/tokens.txt',
          // modelType is left empty on purpose: sherpa-onnx reads it from
          // the model's own metadata, and naming it wrong fails to load.
          // Quiet, because this runs continuously and the default logs
          // every frame.
          debug: false,
        ),
        keywordsFile: '$dir/keywords.txt',
      ),
    );
  }

  /// sherpa-onnx opens models by path, so the bundled assets have to exist
  /// as real files before it can load them.
  Future<String> _materialiseModel() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/kws');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (final name in _assetFiles) {
      final file = File('${dir.path}/$name');
      final data = await rootBundle.load('$_assetDir/$name');
      // Rewritten when the bundled copy differs, so a model or keyword
      // change in an update is picked up instead of the stale copy winning.
      if (file.existsSync() && file.lengthSync() == data.lengthInBytes) {
        continue;
      }
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return dir.path;
  }

  void _onFrame(Uint8List frame) {
    try {
      _handleFrame(frame);
    } on Object catch (error) {
      // Thrown inside a stream callback, this would otherwise vanish into
      // the zone rather than reaching onError, and the wake word would just
      // silently never fire.
      lastError = '$error';
    }
  }

  void _handleFrame(Uint8List frame) {
    if (frame.isEmpty) return;
    framesSeen++;
    samplesSeen += frame.lengthInBytes ~/ 2;

    if (_capturing) {
      _captureFrame(frame);
      return;
    }

    final stream = _kwsStream;
    final spotter = _spotter;
    if (stream == null || spotter == null) return;

    final samples = _toFloat(frame);
    final level = _rms(frame);
    if (level > peakLevel) peakLevel = level;

    // Before the spotter, because a clap has to be judged on the frame it
    // landed on and the spotter's decode loop can span several.
    if (clapToWake && _clap.accept(level, frame.length)) {
      clapDetections++;
      detections++;
      // The decoder holds whatever it had half-heard; leaving it would let
      // it fire again on its own tail once capture ends.
      spotter.reset(stream);
      _beginCapture();
      return;
    }

    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    while (spotter.isReady(stream)) {
      spotter.decode(stream);
      // Checked after every decode, not once the loop drains. The result is
      // cleared by the following decode, so reading it afterwards can step
      // straight over the frame the keyword landed on.
      if (spotter.getResult(stream).keyword.isNotEmpty) {
        // Reset, or the same phrase keeps re-firing on the decoder's tail.
        spotter.reset(stream);
        detections++;
        _beginCapture();
        return;
      }
    }
  }

  void _beginCapture() {
    _capturing = true;
    _captured.clear();
    _capturedBytes = 0;
    _silentBytes = 0;
    _sinceWakeBytes = 0;
    _heardAnything = false;
  }

  void _captureFrame(Uint8List frame) {
    _captured.add(frame);
    _capturedBytes += frame.length;
    _sinceWakeBytes += frame.length;

    final level = _rms(frame);
    if (level > peakLevel) peakLevel = level;
    final speaking = level > math.max(_noiseFloor * 2.5, 0.010);

    if (speaking) {
      _heardAnything = true;
      _silentBytes = 0;
    } else {
      _noiseFloor = _noiseFloor * 0.95 + level * 0.05;
      _silentBytes += frame.length;
    }

    // Nothing was said after the wake word: drop it rather than upload a
    // few seconds of room tone.
    if (!_heardAnything && _sinceWakeBytes >= _bytes(commandGracePeriod)) {
      _endCapture(emit: false);
      return;
    }

    if (_heardAnything && _silentBytes >= _bytes(trailingSilence)) {
      _endCapture(emit: true);
      return;
    }

    if (_capturedBytes >= _bytes(maxCommand)) {
      _endCapture(emit: _heardAnything);
    }
  }

  void _endCapture({required bool emit}) {
    final frames = List<Uint8List>.of(_captured);
    _resetCapture();
    if (emit && frames.isNotEmpty) _commands?.add(encodeWav(frames));
  }

  void _resetCapture() {
    _capturing = false;
    _captured.clear();
    _capturedBytes = 0;
    _silentBytes = 0;
    _sinceWakeBytes = 0;
    _heardAnything = false;
    // The half-detected spike is dropped with the capture, but the
    // refractory count is not: a clap's echo arrives after the capture it
    // opened, and would otherwise open a second one.
    _clap.dropPendingSpike();
  }

  static int _bytes(Duration duration) =>
      (duration.inMilliseconds * sampleRate * _bytesPerSample) ~/ 1000;

  /// Signed 16-bit LE view of a frame.
  ///
  /// Copies when the buffer does not start on a 2-byte boundary, because
  /// `asInt16List` throws on an odd offset and there is no guarantee about
  /// how the platform hands these over.
  static Int16List _asSamples(Uint8List frame) {
    final count = frame.lengthInBytes ~/ 2;
    if (frame.offsetInBytes.isEven) {
      return frame.buffer.asInt16List(frame.offsetInBytes, count);
    }
    return Int16List.view(Uint8List.fromList(frame).buffer, 0, count);
  }

  /// Signed 16-bit LE to the -1..1 floats sherpa-onnx expects.
  static Float32List _toFloat(Uint8List frame) {
    final samples = _asSamples(frame);
    final out = Float32List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = samples[i] / 32768.0;
    }
    return out;
  }

  static double _rms(Uint8List frame) {
    final samples = _asSamples(frame);
    if (samples.isEmpty) return 0;
    var sum = 0.0;
    for (final sample in samples) {
      final normalised = sample / 32768.0;
      sum += normalised * normalised;
    }
    return math.sqrt(sum / samples.length);
  }

  /// Wraps raw PCM in the 44-byte RIFF header the transcription API expects.
  static Uint8List encodeWav(List<Uint8List> frames) {
    final dataLength = frames.fold<int>(0, (sum, f) => sum + f.length);
    const headerLength = 44;
    final out = Uint8List(headerLength + dataLength);
    final view = ByteData.view(out.buffer);

    void ascii(int offset, String tag) {
      for (var i = 0; i < tag.length; i++) {
        out[offset + i] = tag.codeUnitAt(i);
      }
    }

    const channels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;

    ascii(0, 'RIFF');
    view.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    view.setUint32(16, 16, Endian.little);
    view.setUint16(20, 1, Endian.little);
    view.setUint16(22, channels, Endian.little);
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, byteRate, Endian.little);
    view.setUint16(32, blockAlign, Endian.little);
    view.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    view.setUint32(40, dataLength, Endian.little);

    var offset = headerLength;
    for (final frame in frames) {
      out.setRange(offset, offset + frame.length, frame);
      offset += frame.length;
    }
    return out;
  }
}

/// Decides whether a run of frame levels contains a clap.
///
/// Its own class so the thresholds can be exercised directly: driving this
/// through [WakeWordListener] would mean a microphone and a loaded ONNX
/// model to test three floating-point comparisons.
///
/// Stateful by necessity — a clap is a shape across frames, not a property
/// of one — so a detector belongs to a single listening session and is
/// [reset] when that session restarts.
class ClapDetector {
  /// How far above the running noise floor a frame has to jump to be a
  /// clap candidate.
  ///
  /// A clap is not merely loud — speech is loud too. What separates them is
  /// the ratio: a clap is a step change of roughly 20dB inside a single
  /// 20ms frame, where a spoken syllable ramps over several.
  static const double riseRatio = 8.0;

  /// The absolute floor a clap must also clear, so a jump out of near
  /// silence in a very quiet room is not counted.
  static const double minLevel = 0.16;

  /// A clap is over almost immediately. A frame this loud that is *still*
  /// loud two frames later is a door, a shout or music, and is rejected —
  /// which is the check that stops the feature firing all day.
  static const double decayRatio = 0.35;

  /// Frames examined after the spike to see whether it decayed.
  static const int decayFrames = 3;

  /// Nothing can re-trigger a clap for this long after one fires. Covers
  /// the second half of a double clap and the room's own echo.
  static const Duration refractory = Duration(milliseconds: 1200);


  /// The room while nothing is happening. Follows slowly, so a fan starting
  /// up raises the bar for a clap instead of triggering one.
  double idleFloor = 0.01;

  /// A spike waiting to be confirmed or rejected by what follows it.
  double? _peak;
  int _framesLeft = 0;

  /// Frames still to ignore after a clap fired.
  int _cooldownFrames = 0;

  void reset() {
    idleFloor = 0.01;
    _peak = null;
    _framesLeft = 0;
    _cooldownFrames = 0;
  }

  /// Forgets a spike that has not resolved, keeping the refractory count.
  void dropPendingSpike() {
    _peak = null;
    _framesLeft = 0;
  }

  /// Whether the frame at [level] completes a clap.
  ///
  /// Three tests, and it takes all three, because any one alone fires on
  /// something ordinary:
  ///
  ///   * a step of [riseRatio] over the idle room, which rejects speech —
  ///     a syllable ramps across frames rather than jumping inside one;
  ///   * an absolute level over [minLevel], which rejects a jump out of
  ///     near silence in a very quiet room;
  ///   * a decay back under [decayRatio] of the peak within [decayFrames],
  ///     which rejects everything that is loud and *stays* loud — a door, a
  ///     shout, a bass note, music.
  ///
  /// The decay test is why this returns false on the loud frame itself and
  /// true a frame or two later: the shape is not knowable at the peak.
  /// Those frames are the start of the capture buffer anyway, so nothing
  /// spoken immediately after the clap is lost.
  bool accept(double level, int frameBytes) {
    if (_cooldownFrames > 0) {
      _cooldownFrames--;
      _trackIdle(level);
      return false;
    }

    final peak = _peak;
    if (peak != null) {
      _framesLeft--;
      if (level <= peak * decayRatio) {
        // It rose and fell inside a handful of frames. That is a clap.
        _peak = null;
        _framesLeft = 0;
        _cooldownFrames = _framesIn(refractory, frameBytes);
        return true;
      }
      if (_framesLeft <= 0) {
        // Still loud. Whatever it was, it was not a clap — and it has been
        // raising the idle floor the whole time, which is correct.
        _peak = null;
        _trackIdle(level);
      }
      return false;
    }

    if (level >= minLevel && level >= idleFloor * riseRatio) {
      _peak = level;
      _framesLeft = decayFrames;
      return false;
    }

    _trackIdle(level);
    return false;
  }

  void _trackIdle(double level) {
    idleFloor = idleFloor * 0.97 + level * 0.03;
  }

  static int _framesIn(Duration duration, int frameBytes) {
    if (frameBytes <= 0) return 0;
    final bytes =
        (duration.inMilliseconds * WakeWordListener.sampleRate * 2) ~/ 1000;
    return (bytes / frameBytes).ceil();
  }
}
