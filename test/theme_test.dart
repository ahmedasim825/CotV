// `defaultTargetPlatform` is not in material.dart's re-export show-list.
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/ui/theme/app_theme.dart';
import 'package:cotv/src/ui/widgets/ph_light_icons.dart';

void main() {
  test('buildAppTheme can override the scaffold floor, and defaults to the '
      'palette ground', () {
    expect(
      buildAppTheme(background: const Color(0xFF120323))
          .scaffoldBackgroundColor,
      const Color(0xFF120323),
    );
    // Nothing supplied — the app itself takes this path, and so does every
    // test that builds a bare theme.
    expect(buildAppTheme().scaffoldBackgroundColor, kPalette.background);
  });

  test('the palette is the mock purple on the mock ground', () {
    expect(kPalette.accent, const Color(0xFF7005BB));
    expect(kPalette.background, const Color(0xFF191717));
    expect(kPalette.brightness, Brightness.dark);
  });

  test('the agenda rings are the mock hues, not the app reds and violets', () {
    // The merged Tasks / Reminders card draws no headings and no separator
    // between kinds, so these two values are the entire signal distinguishing
    // a task row from a reminder row.
    expect(kPalette.taskRing, const Color(0xFFFFE100));
    expect(kPalette.reminderRing, const Color(0xFFFF0000));
    // Distinct from `danger`: that one means "something is wrong", this one
    // means "this row is a reminder".
    expect(kPalette.reminderRing, isNot(kPalette.danger));
  });

  test('buildAppTheme pins no platform, which is what gates the iOS shell', () {
    // `context.useLiquidGlass` reads `ThemeData.platform`. Because nothing
    // sets it here, it falls through to `defaultTargetPlatform` — Android
    // under flutter_test — so every pre-existing test in this suite keeps
    // exercising the Windows path without knowing the iOS one exists, and an
    // iOS test opts in explicitly with the copyWith below.
    //
    // If anyone ever passes `platform:` in buildAppTheme, roughly thirty
    // assertions across five files flip at once. This is the test that says
    // why.
    expect(buildAppTheme().platform, defaultTargetPlatform);
    expect(defaultTargetPlatform, isNot(TargetPlatform.iOS));
    expect(
      buildAppTheme().copyWith(platform: TargetPlatform.iOS).platform,
      TargetPlatform.iOS,
    );
  });

  testWidgets('useLiquidGlass follows the theme platform, nothing else', (
    tester,
  ) async {
    Future<bool> glassUnder(ThemeData theme) async {
      late bool seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              seen = context.useLiquidGlass;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // MaterialApp wraps its theme in an AnimatedTheme, and `ThemeData.lerp`
      // switches `platform` at the midpoint — so the first frame after a theme
      // change still reports the *previous* platform. Pump past the animation
      // before reading, or every call after the first returns the one before
      // it.
      await tester.pump(const Duration(seconds: 1));
      return seen;
    }

    expect(await glassUnder(buildAppTheme()), isFalse);
    expect(
      await glassUnder(buildAppTheme().copyWith(platform: TargetPlatform.iOS)),
      isTrue,
    );
    expect(
      await glassUnder(
        buildAppTheme().copyWith(platform: TargetPlatform.macOS),
      ),
      isFalse,
      reason: 'the shell is iPhone and iPad only',
    );
  });

  testWidgets('buildAppTheme takes no variant and carries the palette', (
    tester,
  ) async {
    late AppPalette seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) {
            seen = context.palette;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(seen.accent, const Color(0xFF7005BB));
  });

  test('every new glyph is a real Phosphor codepoint', () {
    const glyphs = <IconData>[
      PhLight.list,
      PhLight.sidebarSimple,
      PhLight.clockCounterClockwise,
      PhLight.books,
      PhLight.skipBack,
      PhLight.skipForward,
      PhLight.play,
      PhLight.pause,
      PhLight.cloud,
      PhLight.speakerLow,
      PhLight.speakerNone,
      PhLight.starAndCrescent,
      PhLight.musicNotes,
    ];
    for (final glyph in glyphs) {
      expect(glyph.fontFamily, 'PhosphorRegular');
      expect(glyph.fontPackage, 'phosphor_flutter');
    }
    // A duplicated codepoint means one was copied into the wrong name.
    final points = glyphs.map((g) => g.codePoint).toSet();
    expect(points.length, glyphs.length);
  });

  test('the heavier cuts are the same glyphs against a different family', () {
    // Phosphor keeps one codepoint per glyph across every weight, which is the
    // whole reason PhBold and PhFill can exist without a second lookup table.
    // If that ever stopped being true, these pairs would silently start drawing
    // the wrong picture, so the equality is asserted rather than assumed.
    expect(PhBold.clockCounterClockwise.fontFamily, 'PhosphorBold');
    expect(
      PhBold.clockCounterClockwise.codePoint,
      PhLight.clockCounterClockwise.codePoint,
    );

    // Records, not a map: IconData overrides `==`, which disqualifies it as a
    // const map key.
    const pairs = <(IconData, IconData)>[
      (PhFill.play, PhLight.play),
      (PhFill.pause, PhLight.pause),
      (PhFill.skipBack, PhLight.skipBack),
      (PhFill.skipForward, PhLight.skipForward),
      (PhFill.speakerHigh, PhLight.speakerHigh),
      (PhFill.speakerLow, PhLight.speakerLow),
      (PhFill.speakerNone, PhLight.speakerNone),
      (PhFill.musicNotes, PhLight.musicNotes),
    ];
    for (final (filled, outline) in pairs) {
      expect(filled.fontFamily, 'PhosphorFill');
      expect(filled.fontPackage, 'phosphor_flutter');
      expect(filled.codePoint, outline.codePoint);
    }

    final points = pairs.map((pair) => pair.$1.codePoint).toSet();
    expect(points.length, pairs.length);
  });
}
