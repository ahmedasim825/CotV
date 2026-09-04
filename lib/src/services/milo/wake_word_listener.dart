import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Listens for "Hey Milo" on device, then captures the command that follows.
///
/// The wake word is spotted by a sherpa-onnx zipformer keyword model running
/// locally, not by uploading audio and reading the transcript. That is the
/// whole point: **nothing leaves the machine until the phrase actually
/// matches.** Ambient conversation is decoded on device and discarded.
///
/// Keywords are BPE token sequences rather than a trained model, so adding a
/// phrase is a line in `assets/kws/keywords.txt` and needs no training run.
///
/// One microphone stream serves both jobs. While idle every frame goes to
/// the spotter; once it fires, frames are buffered instead until the speaker
/// stops, and that buffer — only that buffer — is handed back to be
/// transcribed.
class WakeWordListener {
  WakeWordListener({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

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
  String? lastError;

  bool _capturing = false;
  final List<Uint8List> _captured = [];
  int _capturedBytes = 0;
  int _silentBytes = 0;
  int _sinceWakeBytes = 0;
  bool _heardAnything = false;
  double _noiseFloor = 0.01;

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
    lastError = null;
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
