import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cotv/src/models/milo_models.dart';
import 'package:cotv/src/providers/milo_providers.dart';
import 'package:cotv/src/ui/app_shell.dart';
import 'package:cotv/src/ui/home/widgets/milo_orb.dart';
import 'package:cotv/src/ui/shell/milo_dock.dart';
import 'package:cotv/src/ui/shell/sidebar.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildAppTheme(),
  home: Scaffold(body: child),
);

/// A stand-in for [MiloConversationNotifier] that never touches
/// [chatRepositoryProvider], hence never touches Hive.
///
/// The real notifier's `build()` does not reach Hive either — it only
/// returns an empty [MiloConversation] — but the dock is exercised here as a
/// bare widget test with no Hive box ever opened, so pinning the state this
/// way keeps the test from depending on that being true forever.
class _FakeMiloConversationNotifier extends MiloConversationNotifier {
  @override
  MiloConversation build() => const MiloConversation(
    messages: [
      MiloMessage(id: 'm1', role: MiloRole.assistant, text: 'Asr is at 4:12.'),
    ],
  );
}

final _dockOverrides = [
  miloConversationProvider.overrideWith(_FakeMiloConversationNotifier.new),
];

void main() {
  testWidgets('expanded shows five labels and hides Settings from the list', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Sidebar(
          mode: SidebarMode.expanded,
          destination: AppDestination.home,
          onSelect: (_) {},
        ),
      ),
    );

    for (final label in ['Home', 'Tasks', 'Study', 'Food', 'Prayers']) {
      expect(find.text(label), findsOneWidget);
    }
    // The gear is a footer control, not a sixth row.
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('collapsed drops the labels but keeps the icons', (tester) async {
    await tester.pumpWidget(
      _host(
        Sidebar(
          mode: SidebarMode.collapsed,
          destination: AppDestination.home,
          onSelect: (_) {},
        ),
      ),
    );

    expect(find.text('Home'), findsNothing);
    expect(find.byType(SidebarNavItem), findsNWidgets(5));
  });

  testWidgets('the selected item goes white and is marked at the rail edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Sidebar(
          mode: SidebarMode.expanded,
          destination: AppDestination.tasks,
          onSelect: (_) {},
        ),
      ),
    );

    final selected = tester.widget<SidebarNavItem>(
      find.widgetWithText(SidebarNavItem, 'Tasks'),
    );
    expect(selected.isSelected, isTrue);

    // White, not the accent: the violet lives in the box's stroke and the
    // edge nub now, and #7005BB text inside a violet-lit box read as muddy.
    final label = tester.widget<Text>(find.text('Tasks'));
    expect(label.style?.color, kPalette.textPrimary);
    expect(label.style?.color, const Color(0xFFFFFFFF));

    // The glyph takes the same colour, so the two never disagree.
    final icon = tester.widget<Icon>(
      find.descendant(of: find.byWidget(selected), matching: find.byType(Icon)),
    );
    expect(icon.color, kPalette.textPrimary);

    // The glowing nub against the rail's left edge, on the selected row only.
    // The stroked box around the row is painted rather than built, so this key
    // is the whole structural signal selection leaves in the tree.
    expect(
      find.descendant(
        of: find.byWidget(selected),
        matching: find.byKey(const ValueKey('sidebar-active-tab')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('sidebar-active-tab')), findsOneWidget);
  });

  // The selection cross-fade, on rows that have nothing to do with Home.
  //
  // A cut and a 200ms fade look identical at rest, so this pumps to the middle
  // of the fade and asserts both rows are part-way between the two colours —
  // which a cut can never be.
  testWidgets('selection eases between any two tabs, not just out of Home', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const _SwitchingRail(
          from: AppDestination.study,
          to: AppDestination.food,
        ),
      ),
    );

    Color labelOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;

    expect(labelOf('Study'), kPalette.textPrimary);
    expect(labelOf('Food'), kPalette.textMuted);

    tester.state<_SwitchingRailState>(find.byType(_SwitchingRail)).switchOver();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Half way: neither row is at either end.
    for (final label in ['Study', 'Food']) {
      expect(labelOf(label), isNot(kPalette.textPrimary), reason: label);
      expect(labelOf(label), isNot(kPalette.textMuted), reason: label);
    }

    // And it lands.
    await tester.pump(const Duration(milliseconds: 200));
    expect(labelOf('Food'), kPalette.textPrimary);
    expect(labelOf('Study'), kPalette.textMuted);
  });

  testWidgets('tapping a destination reports it once', (tester) async {
    final taps = <AppDestination>[];
    await tester.pumpWidget(
      _host(
        Sidebar(
          mode: SidebarMode.expanded,
          destination: AppDestination.home,
          onSelect: taps.add,
        ),
      ),
    );

    await tester.tap(find.text('Food'));
    expect(taps, [AppDestination.food]);
  });

  testWidgets('the dock shows the title, a Chat button and the orb', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: _dockOverrides,
        child: _host(const MiloDock(showLabels: true)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Milo'), findsOneWidget);
    expect(find.text('Chat >'), findsOneWidget);
    expect(find.byType(MiloOrbWidget), findsOneWidget);
    // `_FakeMiloConversationNotifier` seeds this exact last message
    // specifically to exercise the dock's `lastLine` branch — assert it
    // actually renders rather than only that the branch didn't crash.
    expect(find.text('Asr is at 4:12.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapsed, the dock is the orb alone, with a way into the panel',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: _dockOverrides,
          child: _host(const MiloDock(showLabels: false)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Milo'), findsNothing);
      expect(find.text('Chat >'), findsNothing);
      expect(find.byType(MiloOrbWidget), findsOneWidget);
      // The orb's own tap opens the microphone, not the panel (see
      // `MiloOrb.onTap`), so collapsed still needs its own tappable way in.
      expect(find.byTooltip('Open Milo chat'), findsOneWidget);
    },
  );
}

/// Drives [Sidebar] through a selection change the way `AppShell` does.
class _SwitchingRail extends StatefulWidget {
  const _SwitchingRail({required this.from, required this.to});

  final AppDestination from;
  final AppDestination to;

  @override
  State<_SwitchingRail> createState() => _SwitchingRailState();
}

class _SwitchingRailState extends State<_SwitchingRail> {
  late AppDestination _destination = widget.from;

  void switchOver() => setState(() => _destination = widget.to);

  @override
  Widget build(BuildContext context) => Sidebar(
    mode: SidebarMode.expanded,
    destination: _destination,
    onSelect: (_) {},
  );
}
