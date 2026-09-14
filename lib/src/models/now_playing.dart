import 'package:flutter/foundation.dart';

/// What the machine is currently playing, and where from.
///
/// Filled from the Windows media session, which is whatever app last took the
/// system transport — Spotify, a browser tab, a game. Every field here is
/// something Windows actually reports; see [NowPlaying.fromSnapshot] for the
/// two that are derived rather than read.
@immutable
class NowPlaying {
  const NowPlaying({
    required this.sourceApp,
    required this.title,
    required this.artist,
    required this.isPlaying,
    required this.volume,
    this.album = '',
    this.artwork,
    this.artworkUrl,
    this.position = Duration.zero,
    this.duration,
    this.positionUpdatedAt,
    this.canSeek = false,
    this.canGoNext = false,
    this.canGoPrevious = false,
  });

  /// The app the audio belongs to, cleaned up for display — "Spotify",
  /// "Chrome". Shown verbatim.
  ///
  /// Deliberately the app and not the website. The media session API exposes
  /// no origin, so a YouTube tab is indistinguishable from any other Chrome
  /// tab; claiming "youtube.com" would mean guessing.
  final String sourceApp;

  final String title;
  final String artist;
  final String album;
  final bool isPlaying;

  /// System output level, 0..1.
  ///
  /// The system's, not this track's: the media session API carries no volume,
  /// so this comes from Core Audio's default endpoint.
  final double volume;

  /// Raw thumbnail bytes from the session, when it offered one.
  final Uint8List? artwork;

  /// Set only by the Spotify path, which has full-resolution art the system
  /// thumbnail does not.
  final String? artworkUrl;

  /// Where playback was at [positionUpdatedAt] — not a live value.
  ///
  /// Windows refreshes the timeline sparsely, so reading this directly makes
  /// the scrubber jump in steps. [livePosition] is what the UI should show.
  final Duration position;

  /// Null when the source reports no end time, which is normal for streams.
  final Duration? duration;

  final DateTime? positionUpdatedAt;

  /// Whether the source accepts a seek at all. Advisory from the session:
  /// Spotify honours it, several browsers do not, and a scrubber that silently
  /// does nothing is worse than one that is visibly disabled.
  final bool canSeek;

  final bool canGoNext;
  final bool canGoPrevious;

  /// [position] advanced to now, which is what a moving scrubber needs.
  ///
  /// Only advances while playing — a paused track sits where it was left. Runs
  /// off the caller's [now] rather than reading the clock itself, so a widget
  /// can drive it from the app's one-second ticker instead of every field
  /// sampling its own slightly different idea of the time.
  Duration livePosition(DateTime now) {
    if (!isPlaying || positionUpdatedAt == null) return position;
    final elapsed = now.difference(positionUpdatedAt!);
    if (elapsed.isNegative) return position;
    final live = position + elapsed;
    final total = duration;
    if (total != null && live > total) return total;
    return live;
  }

  /// Identifies the track for caching, without depending on an id the session
  /// does not provide.
  String get trackKey => '$sourceApp|$title|$artist|$album';

  NowPlaying copyWith({
    String? sourceApp,
    String? title,
    String? artist,
    String? album,
    bool? isPlaying,
    double? volume,
    Uint8List? artwork,
    String? artworkUrl,
    Duration? position,
    Duration? duration,
    DateTime? positionUpdatedAt,
    bool? canSeek,
    bool? canGoNext,
    bool? canGoPrevious,
  }) {
    return NowPlaying(
      sourceApp: sourceApp ?? this.sourceApp,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      isPlaying: isPlaying ?? this.isPlaying,
      volume: volume ?? this.volume,
      artwork: artwork ?? this.artwork,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      positionUpdatedAt: positionUpdatedAt ?? this.positionUpdatedAt,
      canSeek: canSeek ?? this.canSeek,
      canGoNext: canGoNext ?? this.canGoNext,
      canGoPrevious: canGoPrevious ?? this.canGoPrevious,
    );
  }

  /// Builds from the native bridge's JSON, tolerating every field being wrong.
  ///
  /// Nothing here throws on bad input. The payload comes from whatever app
  /// happens to be playing, by way of Windows, and a malformed title should
  /// leave the card empty rather than take the page down.
  static NowPlaying? fromSnapshot(
    Map<String, dynamic> json, {
    Uint8List? artwork,
    double volume = 0,
  }) {
    final title = _string(json['title']);
    final artist = _string(json['artist']);
    // A session with no title at all is a source that registered with Windows
    // and then said nothing — a browser tab that has not started, usually.
    if (title.isEmpty && artist.isEmpty) return null;

    final endMs = _int(json['endMs']);
    final startMs = _int(json['startMs']);
    final updatedMs = _int(json['updatedEpochMs']);

    // Some sources report the track as a window into a longer timeline, so the
    // useful duration is the span, not the end.
    final spanMs = endMs - startMs;

    return NowPlaying(
      sourceApp: prettifyAppId(_string(json['sourceAppId'])),
      title: title,
      artist: artist,
      album: _string(json['album']),
      isPlaying: json['isPlaying'] == true,
      volume: volume,
      artwork: artwork != null && artwork.isNotEmpty ? artwork : null,
      position: Duration(milliseconds: _int(json['positionMs']) - startMs),
      duration: spanMs > 0 ? Duration(milliseconds: spanMs) : null,
      positionUpdatedAt: updatedMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(updatedMs)
          : null,
      canSeek: json['canSeek'] == true,
      canGoNext: json['canNext'] == true,
      canGoPrevious: json['canPrevious'] == true,
    );
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

/// Turns a Windows app id into something worth showing a person.
///
/// Windows identifies a session by its AppUserModelId, which is an executable
/// name for a desktop app (`Spotify.exe`) and a long packaged identity for a
/// Store one (`Microsoft.YourPhone_8wekyb3d8bbwe!App`). Neither reads well on
/// a card, so the common ones are named and everything else is cleaned up
/// rather than guessed at.
String prettifyAppId(String appId) {
  if (appId.isEmpty) return 'this device';

  final lower = appId.toLowerCase();
  for (final entry in _knownApps.entries) {
    if (lower.contains(entry.key)) return entry.value;
  }

  // Packaged identity: take the family name before the publisher hash.
  var name = appId;
  final bang = name.indexOf('!');
  if (bang > 0) name = name.substring(0, bang);
  final underscore = name.indexOf('_');
  if (underscore > 0) name = name.substring(0, underscore);
  final dot = name.lastIndexOf('.');
  if (dot > 0 && dot < name.length - 1) name = name.substring(dot + 1);

  if (name.toLowerCase().endsWith('.exe')) {
    name = name.substring(0, name.length - 4);
  }
  if (name.isEmpty) return 'this device';
  return name[0].toUpperCase() + name.substring(1);
}

const Map<String, String> _knownApps = {
  'spotify': 'Spotify',
  'chrome': 'Chrome',
  'msedge': 'Edge',
  'firefox': 'Firefox',
  'brave': 'Brave',
  'vlc': 'VLC',
  'itunes': 'iTunes',
  'applemusic': 'Apple Music',
  'music.ui': 'Media Player',
  'zune': 'Media Player',
  'foobar': 'foobar2000',
  'discord': 'Discord',
  'steam': 'Steam',
};
