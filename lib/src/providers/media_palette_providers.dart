import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import '../ui/theme/app_theme.dart';
import 'media_providers.dart';

/// The colours the music card borrows from the album art.
///
/// Two, not a palette: a [tint] the card washes itself in and an [edge] the
/// scrubber and the rim take. Anything more and the card stops agreeing with
/// the rest of the page.
@immutable
class MediaPalette {
  const MediaPalette({required this.tint, required this.edge});

  /// The card's ground. Already knocked back — the raw dominant colour off a
  /// cover is fully saturated and would fight everything around it.
  final Color tint;

  /// The brighter one, for the played part of the scrubber.
  final Color edge;

  /// What the card looks like with no art to read: the app's own accent, so a
  /// track without a cover is still recognisably this app's card.
  static const MediaPalette fallback = MediaPalette(
    tint: Color(0x1A7005BB),
    edge: Color(0xFFA855F7),
  );
}

/// Pulls [MediaPalette] out of the current track's artwork.
///
/// Keyed on the track rather than the bytes so switching back to a previous
/// track is free, and `autoDispose` so the cache does not outlive the card
/// being on screen.
final mediaPaletteProvider = FutureProvider.autoDispose<MediaPalette>((
  ref,
) async {
  final playing = ref.watch(nowPlayingProvider).value;
  final artwork = playing?.artwork;
  if (playing == null || artwork == null || artwork.isEmpty) {
    return MediaPalette.fallback;
  }

  final cached = _cache[playing.trackKey];
  if (cached != null) return cached;

  final palette = await _extract(artwork);
  _remember(playing.trackKey, palette);
  return palette;
});

/// Small on purpose. This exists so a paused-and-resumed track does not
/// re-decode its cover, not to be a real cache — the art itself is already
/// held by the session.
const int _cacheLimit = 8;
final Map<String, MediaPalette> _cache = <String, MediaPalette>{};

void _remember(String key, MediaPalette palette) {
  if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
  _cache[key] = palette;
}

Future<MediaPalette> _extract(Uint8List bytes) async {
  try {
    final generated = await PaletteGenerator.fromImageProvider(
      MemoryImage(bytes),
      // The cover only has to yield two colours, and a full-resolution decode
      // of every track change is the one part of this that could be felt.
      size: const Size(64, 64),
      maximumColorCount: 8,
    );

    final source =
        generated.vibrantColor?.color ??
        generated.dominantColor?.color ??
        generated.mutedColor?.color;
    if (source == null) return MediaPalette.fallback;

    // Pinned to a band rather than used raw. Covers range from near-black to
    // neon, and either extreme makes the card unreadable — a dark one vanishes
    // into the page, a bright one drowns the title sitting on it.
    final hsl = HSLColor.fromColor(source);
    final edge = hsl
        .withLightness(hsl.lightness.clamp(0.55, 0.78))
        .withSaturation(hsl.saturation.clamp(0.35, 0.9))
        .toColor();

    return MediaPalette(tint: edge.withValues(alpha: 0.16), edge: edge);
  } catch (_) {
    // Undecodable art — a format Flutter will not take, or bytes that got
    // truncated on the way through the channel.
    return MediaPalette.fallback;
  }
}

/// The palette as the card should use it, resolved against the theme.
///
/// [context.palette] is a compile-time const with no override seam, so the
/// borrowed colours cannot be swapped in through the theme and have to be
/// threaded down explicitly. This is the one place that decides how.
MediaPalette resolveMediaPalette(BuildContext context, MediaPalette borrowed) {
  final base = context.palette;
  return MediaPalette(
    tint: Color.alphaBlend(borrowed.tint, base.cardFill),
    edge: borrowed.edge,
  );
}
