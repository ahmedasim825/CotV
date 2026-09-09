import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/ui/theme/app_theme.dart';
import 'package:cotv/src/ui/widgets/ph_light_icons.dart';

void main() {
  test('the palette is the mock purple on the mock ground', () {
    expect(kPalette.accent, const Color(0xFF7005BB));
    expect(kPalette.background, const Color(0xFF1B252E));
    expect(kPalette.brightness, Brightness.dark);
  });

  testWidgets('buildAppTheme takes no variant and carries the palette',
      (tester) async {
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

  test('every new glyph is a real PhosphorLight codepoint', () {
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
      expect(glyph.fontFamily, 'PhosphorLight');
      expect(glyph.fontPackage, 'phosphor_flutter');
    }
    // A duplicated codepoint means one was copied into the wrong name.
    final points = glyphs.map((g) => g.codePoint).toSet();
    expect(points.length, glyphs.length);
  });
}
