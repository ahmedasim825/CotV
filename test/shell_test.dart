import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cotv/src/ui/app_shell.dart';
import 'package:cotv/src/ui/shell/sidebar.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

Widget _host(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    );

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
}
