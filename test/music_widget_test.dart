import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cotv/src/models/now_playing.dart';
import 'package:cotv/src/providers/clock_providers.dart';
import 'package:cotv/src/providers/media_providers.dart';
import 'package:cotv/src/ui/home/widgets/media_scrubber.dart';
import 'package:cotv/src/ui/home/widgets/music_widget.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';
import 'package:cotv/src/ui/widgets/ph_light_icons.dart';

/// The clock the card advances its position against.
///
/// Pinned in every test. `nowTickerProvider` is a one-second `Stream.periodic`,
/// so leaving it live means a frame is always scheduled and `pumpAndSettle`
/// runs to its ten-minute timeout instead of returning.
final _now = DateTime(2026, 9, 14, 12, 0, 0);

/// A transport that records rather than acts.
///
/// The real one reaches a platform channel that does not exist under
/// `flutter_test`; every call would return false through `MissingPluginException`
/// and the card would look identical whether it sent the command or not.
class _RecordingTransport extends MediaTransportController {
  const _RecordingTransport(this.calls, this.seeks);

  final List<String> calls;
  final List<Duration> seeks;

  @override
  Future<bool> playPause() async {
    calls.add('playPause');
    return true;
  }

  @override
  Future<bool> next() async {
    calls.add('next');
    return true;
  }

  @override
  Future<bool> previous() async {
    calls.add('previous');
    return true;
  }

  @override
  Future<bool> seek(Duration position) async {
    calls.add('seek');
    seeks.add(position);
    return true;
  }

  @override
  Future<bool> setVolume(double value) async {
    calls.add('setVolume');
    return true;
  }
}

NowPlaying _track({
  bool isPlaying = true,
  Duration position = const Duration(seconds: 30),
  Duration? duration = const Duration(minutes: 3),
  bool canSeek = true,
  bool canGoNext = true,
  bool canGoPrevious = true,
}) {
  return NowPlaying(
    sourceApp: 'Spotify',
    title: 'Sirens',
    artist: 'Travis Scott',
    isPlaying: isPlaying,
    volume: 0.7,
    position: position,
    duration: duration,
    positionUpdatedAt: _now,
    canSeek: canSeek,
    canGoNext: canGoNext,
    canGoPrevious: canGoPrevious,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  NowPlaying? track,
  MediaTransportController? transport,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: ProviderScope(
        overrides: [
          nowPlayingProvider.overrideWith((ref) => Stream.value(track)),
          nowTickerProvider.overrideWith((ref) => Stream.value(_now)),
          if (transport != null)
            mediaTransportProvider.overrideWithValue(transport),
        ],
        child: const Scaffold(body: MusicWidget()),
      ),
    ),
  );
  // Twice. The override is a `Stream.value`, which lands on a microtask, so on
  // the first frame `nowTickerProvider` still has no value and the card falls
  // back to `DateTime.now()` — which makes every assertion about the elapsed
  // figure depend on the wall clock. It read 0:30 before noon and 3:00 after,
  // because `livePosition` advanced the 30s by the hours since `_now` and
  // clamped to the track duration.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows the source app, the track and the artist', (tester) async {
    await _pump(tester, track: _track());

    expect(find.text('Playing on Spotify'), findsOneWidget);
    expect(find.text('Sirens'), findsOneWidget);
    expect(find.text('Travis Scott'), findsOneWidget);
  });

  testWidgets('the transport sends commands rather than moving local state', (
    tester,
  ) async {
    final calls = <String>[];
    await _pump(
      tester,
      track: _track(),
      transport: _RecordingTransport(calls, <Duration>[]),
    );

    // Playing, so the control offers pause — and it is the filled cut now,
    // because the outline one read as too light beside the artwork.
    expect(find.byIcon(PhFill.pause), findsOneWidget);
    await tester.tap(find.byIcon(PhFill.pause));
    await tester.pump();

    // The glyph does *not* flip here, and that is the point: the card draws
    // what the system reports, so it stays on pause until Windows says the
    // session actually paused. Flipping optimistically would lie whenever the
    // source refused.
    expect(calls, ['playPause']);
    expect(find.byIcon(PhFill.pause), findsOneWidget);

    await tester.tap(find.byIcon(PhFill.skipForward));
    await tester.pump();
    expect(calls, ['playPause', 'next']);
  });

  testWidgets('a paused track offers play', (tester) async {
    await _pump(tester, track: _track(isPlaying: false));

    expect(find.byIcon(PhFill.play), findsOneWidget);
    expect(find.byIcon(PhFill.pause), findsNothing);
  });

  testWidgets('nothing playing renders an idle line, not an empty card', (
    tester,
  ) async {
    await _pump(tester, track: null);

    expect(find.text('Nothing playing'), findsOneWidget);
    expect(find.byType(MediaScrubber), findsNothing);
  });

  testWidgets('fits the header slot in two bands, not three', (tester) async {
    // The card trades width for height: the transport sits beside the text
    // rather than on a row of its own. Pinned because the thing that would
    // quietly undo it is someone moving the transport back under the timeline,
    // which still looks fine in isolation and costs ~35pt on the dashboard.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ProviderScope(
          overrides: [
            nowPlayingProvider.overrideWith((ref) => Stream.value(_track())),
            nowTickerProvider.overrideWith((ref) => Stream.value(_now)),
          ],
          // The width `home_screen.dart` gives it in the two-up header.
          child: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 420, child: MusicWidget()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 118pt as built, against roughly 150 for the three-band version this
    // replaced. The guard sits above that rather than on it — it is here to
    // catch the transport moving back onto a row of its own, not to pin the
    // card to the pixel.
    final height = tester.getSize(find.byType(MusicWidget)).height;
    expect(height, lessThan(125));
  });

  testWidgets('shows elapsed and total', (tester) async {
    await _pump(tester, track: _track());
    expect(find.text('0:30'), findsOneWidget);
    expect(find.text('3:00'), findsOneWidget);
  });

  testWidgets('a stream with no end time reads as dashes', (tester) async {
    // Its own test rather than a second pump in the one above: replacing the
    // tree re-runs the overrides but the stream re-emits on a microtask, so
    // the second assertion would race the first frame.
    await _pump(tester, track: _track(duration: null));

    expect(find.text('-:--'), findsOneWidget);
  });

  testWidgets('dragging the scrubber seeks to where it was let go', (
    tester,
  ) async {
    final seeks = <Duration>[];
    await _pump(
      tester,
      track: _track(),
      transport: _RecordingTransport(<String>[], seeks),
    );

    final scrubber = find.byType(MediaScrubber);
    expect(scrubber, findsOneWidget);

    // Grab the middle and drag most of the way right.
    final box = tester.getRect(scrubber);
    await tester.dragFrom(box.center, Offset(box.width * 0.3, 0));
    await tester.pump();

    expect(seeks, hasLength(1));
    // Past halfway, and inside the track.
    expect(seeks.single, greaterThan(const Duration(minutes: 1, seconds: 30)));
    expect(seeks.single, lessThanOrEqualTo(const Duration(minutes: 3)));
  });

  testWidgets('seeks even when the session never advertised support', (
    tester,
  ) async {
    // The inverse of what this used to assert. The scrubber was gated on the
    // session's own seek flag, which Apple Music leaves false while honouring
    // seeks perfectly well — so the bar was dead there and worked in Spotify
    // and Chrome. Attempting it and being ignored is the cheaper failure.
    final seeks = <Duration>[];
    await _pump(
      tester,
      track: _track(canSeek: false),
      transport: _RecordingTransport(<String>[], seeks),
    );

    final box = tester.getRect(find.byType(MediaScrubber));
    await tester.dragFrom(box.center, Offset(box.width * 0.3, 0));
    await tester.pump();

    expect(seeks, hasLength(1));
  });

  testWidgets('skip controls grey out when the session has no queue', (
    tester,
  ) async {
    final calls = <String>[];
    await _pump(
      tester,
      track: _track(canGoNext: false, canGoPrevious: false),
      transport: _RecordingTransport(calls, <Duration>[]),
    );

    await tester.tap(find.byIcon(PhFill.skipForward));
    await tester.pump();
    expect(calls, isEmpty, reason: 'a disabled control must not fire');
  });

  // The volume popup holds its own drag position rather than reading the prop.
  //
  // Nothing about volume makes `nowPlayingProvider` emit, so the card never
  // rebuilds to hand the popup a fresh value mid-drag — and the popup is an
  // Overlay-rooted subtree that would not see it anyway. This isolates that.
  testWidgets('the volume slider tracks its own drag', (tester) async {
    await _pump(
      tester,
      track: _track(),
      transport: _RecordingTransport(<String>[], <Duration>[]),
    );

    await tester.tap(find.byIcon(PhFill.speakerHigh));
    await tester.pumpAndSettle();

    // Scoped to the popup: the card's own scrubber is a CustomPaint precisely
    // so that this finder stays unambiguous, but naming the route keeps it
    // that way even if something else here ever grows a slider.
    final slider = find.descendant(
      of: find.byType(PopupMenuItem<void>),
      matching: find.byType(Slider),
    );
    expect(slider, findsOneWidget);

    final before = tester.widget<Slider>(slider).value;
    await tester.drag(slider, const Offset(-40, 0));
    await tester.pump();

    expect(tester.widget<Slider>(slider).value, lessThan(before));
  });
}
