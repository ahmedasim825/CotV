import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/now_playing.dart';

/// The transport the music widget drives.
///
/// Sample state for now: this build is frontend only, and reading real
/// now-playing metadata on Windows means the System Media Transport Controls,
/// which is a platform channel this plan does not add. The four methods below
/// are the whole surface a real implementation has to satisfy, but swapping
/// one in does not replace only this class: a real SMTC source is
/// asynchronous, so the watch site's type moves from `NowPlaying?` to
/// `AsyncValue<NowPlaying?>`. The one consumer, `MusicWidget`, currently has
/// only a `playing == null` branch for "nothing playing" — it would need a
/// loading and an error branch added before the swap compiles.
class MediaTransportController extends Notifier<NowPlaying?> {
  @override
  NowPlaying? build() {
    return const NowPlaying(
      sourceApp: 'Spotify',
      title: 'Sirens',
      artist: 'Travis Scott',
      isPlaying: true,
      volume: 0.7,
    );
  }

  void togglePlayPause() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(isPlaying: !current.isPlaying);
  }

  /// A real source would advance the queue. With sample state there is no
  /// queue, so this resumes playback and leaves the track — enough for the
  /// control to be wired and honest about doing nothing else.
  void next() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(isPlaying: true);
  }

  void previous() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(isPlaying: true);
  }

  void setVolume(double value) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(volume: value.clamp(0.0, 1.0));
  }
}

final nowPlayingProvider =
    NotifierProvider<MediaTransportController, NowPlaying?>(
  MediaTransportController.new,
);
