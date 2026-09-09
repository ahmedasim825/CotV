import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cotv/src/models/now_playing.dart';
import 'package:cotv/src/providers/media_providers.dart';
import 'package:cotv/src/ui/home/widgets/music_widget.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';
import 'package:cotv/src/ui/widgets/ph_light_icons.dart';

void main() {
  testWidgets('shows the source app, the track and the artist', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const ProviderScope(child: Scaffold(body: MusicWidget())),
    ));
    await tester.pump();

    expect(find.text('Playing on Spotify'), findsOneWidget);
    expect(find.text('Sirens'), findsOneWidget);
    expect(find.text('Travis Scott'), findsOneWidget);
  });

  testWidgets('the transport button toggles between pause and play',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const ProviderScope(child: Scaffold(body: MusicWidget())),
    ));
    await tester.pump();

    // Playing, so the control offers pause.
    expect(find.byIcon(PhLight.pause), findsOneWidget);
    await tester.tap(find.byIcon(PhLight.pause));
    await tester.pump();
    expect(find.byIcon(PhLight.play), findsOneWidget);
  });

  testWidgets('nothing playing renders an idle line, not an empty card',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: ProviderScope(
        overrides: [nowPlayingProvider.overrideWith(_SilentController.new)],
        child: const Scaffold(body: MusicWidget()),
      ),
    ));
    await tester.pump();

    expect(find.text('Nothing playing'), findsOneWidget);
  });

  // Regression coverage for the volume popup's stateful drag tracking.
  //
  // The obvious test — drag the slider with the real controller and check
  // the end value — does NOT catch a regression back to `Slider(value:
  // widget.volume, ...)`. Verified by hand: reverting `_VolumeControlState`
  // to read `widget.volume` and driving that version of the widget through
  // exactly that kind of test still passes, because `setVolume` updates
  // `nowPlayingProvider`, which makes the (shallow) `MusicWidget` rebuild
  // and hand `_VolumeControl` a fresh `volume` prop *before* Flutter's
  // build pass reaches the (much deeper, Overlay-rooted) popup route on the
  // same frame — so `widget.volume` happens to already be current by the
  // time the popup rereads it. That ordering is incidental to this test
  // harness's tree shape, not a guarantee, and it defeats the very
  // assertion the brief suggested.
  //
  // To actually exercise "the popup keeps up with the drag on its own,
  // without the card rebuilding to hand it a fresh prop," the controller
  // below never touches provider state, so nothing ever gives
  // `_VolumeControl` a new `volume` value mid-drag. Under the correct
  // implementation the slider still tracks the drag, because `_value` is
  // mutated directly on `_VolumeControlState` rather than read from
  // `widget`. Under the regression, `widget.volume` never changes and the
  // slider stays pinned at its starting position — caught below.
  testWidgets(
      'the volume slider tracks the drag from its own state, not a prop '
      'the card would have to rebuild to refresh', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: ProviderScope(
        overrides: [
          nowPlayingProvider.overrideWith(_FrozenVolumeController.new),
        ],
        child: const Scaffold(body: MusicWidget()),
      ),
    ));
    await tester.pump();

    // Sample state starts at volume 0.7, so the glyph is speakerHigh.
    await tester.tap(find.byIcon(PhLight.speakerHigh));
    await tester.pumpAndSettle();

    final sliderFinder = find.byType(Slider);
    expect(sliderFinder, findsOneWidget);
    final startValue = tester.widget<Slider>(sliderFinder).value;

    await tester.drag(sliderFinder, const Offset(-40, 0));
    await tester.pump();

    final draggedValue = tester.widget<Slider>(sliderFinder).value;
    expect(draggedValue, lessThan(startValue));
  });
}

class _SilentController extends MediaTransportController {
  @override
  NowPlaying? build() => null;
}

/// A controller whose `setVolume` never touches provider state.
///
/// Nothing about volume ever makes `nowPlayingProvider` emit, so nothing
/// ever gives `MusicWidget` a reason to rebuild and pass `_VolumeControl` a
/// fresh `volume` prop mid-drag. This isolates the popup slider's own
/// tracking mechanism from that outside channel.
class _FrozenVolumeController extends MediaTransportController {
  @override
  void setVolume(double value) {}
}
