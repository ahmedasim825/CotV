import 'package:flutter/material.dart';

/// The swatches a habit can be given, as the `#RRGGBB` strings stored in
/// [Habit.colorHex].
///
/// Deliberately mid-saturation and mid-lightness: these are the one part of
/// the UI that does not come from the active theme, so each has to stay
/// legible on a true-black canvas and on Pearl's warm white alike.
const List<String> habitColorHexes = [
  '#34D399', // emerald
  '#E5B769', // gold
  '#7FA3B8', // steel
  '#C97A55', // copper
  '#7B8FCB', // indigo
  '#B98BC9', // orchid
  '#8FBF9F', // sage
  '#E2836B', // coral
];

/// Parses a `#RRGGBB` (or `#AARRGGBB`) string into a [Color].
///
/// Returns [fallback] for anything it cannot parse, so a hand-edited or
/// migrated record can never crash the grid.
Color habitColorFromHex(String hex, Color fallback) {
  var value = hex.trim();
  if (value.startsWith('#')) value = value.substring(1);
  if (value.length == 6) value = 'FF$value';
  if (value.length != 8) return fallback;

  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return fallback;
  return Color(parsed);
}
