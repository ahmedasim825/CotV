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
}

class _SilentController extends MediaTransportController {
  @override
  NowPlaying? build() => null;
}
