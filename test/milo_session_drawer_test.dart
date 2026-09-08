// The chat drawer: listing, searching, renaming and deleting threads.
//
// Backed by a real in-memory SQLite database rather than a fake repository,
// so what the list shows is what a query actually returns — the counts and
// the ordering are computed in SQL, and a fake would assert neither.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/src/models/chat_message.dart';
import 'package:cotv/src/providers/chat_session_providers.dart';
import 'package:cotv/src/repositories/chat_session_repository.dart';
import 'package:cotv/src/storage/app_database.dart';
import 'package:cotv/src/ui/milo/widgets/session_drawer.dart';
import 'package:cotv/src/ui/theme/app_theme.dart';

final _epoch = DateTime.utc(2026, 3, 17, 9);

void main() {
  late AppDatabase database;
  late SqliteChatSessionRepository repository;

  setUp(() {
    database = AppDatabase.openAt(':memory:');
    repository = SqliteChatSessionRepository(database);
  });

  tearDown(() {
    repository.dispose();
    database.dispose();
  });

  Future<void> pumpDrawer(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          theme: buildAppTheme(AppThemeVariant.sanctuary),
          home: const Scaffold(
            body: SingleChildScrollView(child: SessionDrawer()),
          ),
        ),
      ),
    );
    // The session stream yields its first value on a microtask.
    await tester.pump();
    await tester.pump();
  }

  Future<void> seed(String title, {int messages = 0, int hour = 9}) async {
    final session = await repository.createSession(
      title: title,
      now: DateTime.utc(2026, 3, 17, hour),
    );
    for (var i = 0; i < messages; i++) {
      await repository.append(
        ChatMessage(
          id: '${session.id}-m$i',
          sessionId: session.id,
          isUser: i.isEven,
          text: 'turn $i in $title',
          timestamp: _epoch.add(Duration(hours: hour, minutes: i)),
        ),
      );
    }
  }

  testWidgets('an empty drawer says so rather than showing a blank list',
      (tester) async {
    await pumpDrawer(tester);

    expect(find.text('No other chats yet'), findsOneWidget);
    expect(find.text('New chat'), findsOneWidget);
  });

  testWidgets('lists threads newest first, with their message counts',
      (tester) async {
    await seed('Cardiology revision', messages: 4, hour: 9);
    await seed('Prayer times', messages: 1, hour: 14);
    await pumpDrawer(tester);

    expect(find.text('Cardiology revision'), findsOneWidget);
    expect(find.text('Prayer times'), findsOneWidget);

    // Singular and plural are not the same word, and a list that says
    // "1 messages" is one nobody proofread.
    expect(find.textContaining('4 messages'), findsOneWidget);
    expect(find.textContaining('1 message ·'), findsOneWidget);

    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(
      titles.indexOf('Prayer times') < titles.indexOf('Cardiology revision'),
      isTrue,
      reason: 'most recently touched thread sorts first',
    );
  });

  testWidgets('an empty thread is labelled, not counted', (tester) async {
    await seed('Untouched');
    await pumpDrawer(tester);

    expect(find.textContaining('Empty ·'), findsOneWidget);
    expect(find.textContaining('0 messages'), findsNothing);
  });

  testWidgets('search matches a title', (tester) async {
    await seed('Cardiology revision', messages: 1, hour: 9);
    await seed('Prayer times', messages: 1, hour: 10);
    await pumpDrawer(tester);

    await tester.enterText(find.byType(TextField), 'cardio');
    await tester.pump();
    await tester.pump();

    expect(find.text('Cardiology revision'), findsOneWidget);
    expect(find.text('Prayer times'), findsNothing);
  });

  testWidgets('search matches text inside a thread, not just its title',
      (tester) async {
    await seed('Untitled one', messages: 0, hour: 9);
    final session = repository.listSessions().first;
    await repository.append(
      ChatMessage(
        id: 'deep',
        sessionId: session.id,
        isUser: true,
        text: 'remind me about the amlodipine dose',
        timestamp: _epoch,
      ),
    );
    await pumpDrawer(tester);

    await tester.enterText(find.byType(TextField), 'amlodipine');
    await tester.pump();
    await tester.pump();

    expect(find.text('Untitled one'), findsOneWidget);
  });

  testWidgets('a search with no hits says so, distinctly from empty',
      (tester) async {
    await seed('Cardiology revision', messages: 1);
    await pumpDrawer(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump();
    await tester.pump();

    expect(find.text('No chats match that'), findsOneWidget);
    expect(find.text('No other chats yet'), findsNothing);
  });

  testWidgets('deleting asks first, and takes the messages with it',
      (tester) async {
    await seed('Cardiology revision', messages: 3);
    await pumpDrawer(tester);

    final session = repository.listSessions().single;
    expect(repository.messageCount(session.id), 3);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    // Confirmed, not immediate — and the copy says what is being lost.
    expect(find.textContaining('3 messages'), findsWidgets);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(repository.listSessions(), isEmpty);
    expect(repository.messageCount(session.id), 0);
  });

  testWidgets('cancelling a delete keeps the thread', (tester) async {
    await seed('Cardiology revision', messages: 3);
    await pumpDrawer(tester);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(repository.listSessions(), hasLength(1));
  });

  testWidgets('renaming writes the new title', (tester) async {
    await seed('Untitled one', messages: 1);
    await pumpDrawer(tester);

    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Cardiology');
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();

    expect(repository.listSessions().single.title, 'Cardiology');
  });

  testWidgets('a cancelled rename does not touch the row', (tester) async {
    await seed('Untitled one', messages: 1);
    await pumpDrawer(tester);
    final before = repository.listSessions().single;

    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    final after = repository.listSessions().single;
    expect(after.title, before.title);
    // updated_at orders the drawer, so a cancelled rename must not reorder
    // the list by touching it.
    expect(after.updatedAt, before.updatedAt);
  });
}
