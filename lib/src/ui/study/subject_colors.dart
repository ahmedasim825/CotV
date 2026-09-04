import 'package:flutter/material.dart';

/// The swatches a subject can be given, as the 32-bit ARGB ints stored in
/// [Subject.colorValue].
///
/// The same set the habit grid uses, for the same reason: these are the one
/// part of the UI that does not come from the active theme, so each has to
/// stay legible on a true-black canvas and on Pearl's warm white alike.
/// Kept as ints rather than the hex strings habits store because that is
/// the form [Subject] persists, and a round trip through a string would
/// only add a way to fail.
const List<int> subjectColorValues = [
  0xFF7B8FCB, // indigo
  0xFF34D399, // emerald
  0xFFE5B769, // gold
  0xFFC97A55, // copper
  0xFF7FA3B8, // steel
  0xFFB98BC9, // orchid
  0xFF8FBF9F, // sage
  0xFFE2836B, // coral
];

/// The colour a subject renders in.
Color subjectColor(int value) => Color(value);
