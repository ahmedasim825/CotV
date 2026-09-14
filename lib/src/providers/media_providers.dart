import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/now_playing.dart';

/// Commands for whatever the machine is playing.
const MethodChannel mediaChannel = MethodChannel('cotv/media');

/// The now-playing stream.
///
/// An [EventChannel] rather than a polled method, because Windows pushes: the
/// native bridge subscribes to the session's own change events and only speaks
/// when something moved. Polling it once a second would wake the app for a
/// value that changes when a track ends.
const EventChannel mediaEventChannel = EventChannel('cotv/media/events');

/// What the machine is playing, or null when nothing is.
///
/// Windows only. On every other platform the channel is not implemented and
/// this stays null forever, which is the right answer — the card is not built
/// off Windows anyway.
final nowPlayingProvider = StreamProvider<NowPlaying?>((ref) async* {
  // Seeded so the card has something to draw on frame one rather than sitting
  // in a loading state until the first change event.
  double volume = await _readVolume();

  await for (final event in mediaEventChannel.receiveBroadcastStream()) {
    if (event == null) {
      yield null;
      continue;
    }
    if (event is! Map) {
      yield null;
      continue;
    }

    // Volume is not part of the snapshot — it comes from a different subsystem
    // entirely — so it is re-read as tracks change rather than streamed.
    volume = await _readVolume(fallback: volume);

    yield _decode(event, volume);
  }
});

NowPlaying? _decode(Map<Object?, Object?> event, double volume) {
  final raw = event['json'];
  if (raw is! String || raw.isEmpty) return null;

  Map<String, dynamic> json;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    json = decoded;
  } on FormatException {
    // A title with a stray control character should cost the card its
    // metadata, not the whole stream.
    return null;
  }

  final art = event['artwork'];
  return NowPlaying.fromSnapshot(
    json,
    artwork: art is Uint8List ? art : null,
    volume: volume,
  );
}

Future<double> _readVolume({double fallback = 0}) async {
  try {
    final value = await mediaChannel.invokeMethod<double>('getVolume');
    return value ?? fallback;
  } on PlatformException {
    return fallback;
  } on MissingPluginException {
    return fallback;
  }
}

/// Drives the transport.
///
/// Every call is best-effort and returns whether the source accepted it. A
/// session can vanish between the card being drawn and a button being pressed
/// — the app closed, the tab went away — and that is ordinary, not an error
/// worth surfacing.
class MediaTransportController {
  const MediaTransportController();

  Future<bool> playPause() => _send('playPause');
  Future<bool> next() => _send('next');
  Future<bool> previous() => _send('previous');

  Future<bool> seek(Duration position) =>
      _send('seek', {'positionMs': position.inMilliseconds});

  Future<bool> setVolume(double value) =>
      _send('setVolume', {'volume': value.clamp(0.0, 1.0)});

  Future<bool> _send(String method, [Map<String, Object?>? arguments]) async {
    try {
      final ok = await mediaChannel.invokeMethod<bool>(method, arguments);
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Not Windows. The card is not built there either.
      return false;
    }
  }
}

final mediaTransportProvider = Provider<MediaTransportController>(
  (ref) => const MediaTransportController(),
);
