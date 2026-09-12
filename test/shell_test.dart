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
          MiloMessage(
            id: 'm1',
            role: MiloRole.assistant,
            text: 'Asr is at 4:12.',
          ),
        ],
      );
}

final _dockOverrides = [
  miloConversationProvider.overrideWith(_FakeMiloConversationNotifier.new),
];

void main() {
  testWidgets('expanded shows five labels and hides Settings from the list',
      (tester) async {
    await tester.pumpWidget(_host(Sidebar(
      mode: SidebarMode.expanded,
      destination: AppDestination.home,
      onSelect: (_) {},
      onToggleCollapse: () {},
      onToggleHidden: () {},
    )));

    for (final label in ['Home', 'Tasks', 'Study', 'Food', 'Prayers']) {
      expect(find.text(label), findsOneWidget);
    }
    // The gear is a footer control, not a sixth row.
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('collapsed drops the labels but keeps the icons', (tester) async {
    await tester.pumpWidget(_host(Sidebar(
      mode: SidebarMode.collapsed,
      destination: AppDestination.home,
      onSelect: (_) {},
      onToggleCollapse: () {},
      onToggleHidden: () {},
    )));

    expect(find.text('Home'), findsNothing);
    expect(find.byType(SidebarNavItem), findsNWidgets(5));
  });

  testWidgets('the selected item is accented and underlined', (tester) async {
    await tester.pumpWidget(_host(Sidebar(
      mode: SidebarMode.expanded,
      destination: AppDestination.tasks,
      onSelect: (_) {},
      onToggleCollapse: () {},
      onToggleHidden: () {},
    )));

    final selected = tester.widget<SidebarNavItem>(
      find.widgetWithText(SidebarNavItem, 'Tasks'),
    );
    expect(selected.isSelected, isTrue);

    final label = tester.widget<Text>(find.text('Tasks'));
    expect(label.style?.color, kPalette.accent);

    // The underline is a 2pt box under the selected icon only.
    expect(
      find.descendant(
        of: find.byWidget(selected),
        matching: find.byKey(const ValueKey('sidebar-underline')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping a destination reports it once', (tester) async {
    final taps = <AppDestination>[];
    await tester.pumpWidget(_host(Sidebar(
      mode: SidebarMode.expanded,
      destination: AppDestination.home,
      onSelect: taps.add,
      onToggleCollapse: () {},
      onToggleHidden: () {},
    )));

    await tester.tap(find.text('Food'));
    expect(taps, [AppDestination.food]);
  });

  testWidgets('the dock shows the title, a Chat button and the orb',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _dockOverrides,
      child: _host(const MiloDock(showLabels: true)),
    ));
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

  testWidgets('collapsed, the dock is the orb alone, with a way into the panel',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _dockOverrides,
      child: _host(const MiloDock(showLabels: false)),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Milo'), findsNothing);
    expect(find.text('Chat >'), findsNothing);
    expect(find.byType(MiloOrbWidget), findsOneWidget);
    // The orb's own tap opens the microphone, not the panel (see
    // `MiloOrb.onTap`), so collapsed still needs its own tappable way in.
    expect(find.byTooltip('Open Milo chat'), findsOneWidget);
  });
}
