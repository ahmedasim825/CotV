import 'package:flutter/foundation.dart';

/// What the machine is currently playing, and where from.
@immutable
class NowPlaying {
  const NowPlaying({
    required this.sourceApp,
    required this.title,
    required this.artist,
    required this.isPlaying,
    required this.volume,
    this.artworkUrl,
  });

  /// The app the audio belongs to — "Spotify", "YouTube". Shown verbatim.
  final String sourceApp;
  final String title;
  final String artist;
  final bool isPlaying;

  /// 0..1.
  final double volume;

  /// Null when the source gave no artwork, which is common. The widget draws
  /// a note glyph in that case rather than a broken image.
  final String? artworkUrl;

  NowPlaying copyWith({
    String? sourceApp,
    String? title,
    String? artist,
    bool? isPlaying,
    double? volume,
    String? artworkUrl,
  }) {
    return NowPlaying(
      sourceApp: sourceApp ?? this.sourceApp,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      isPlaying: isPlaying ?? this.isPlaying,
      volume: volume ?? this.volume,
      artworkUrl: artworkUrl ?? this.artworkUrl,
    );
  }
}
