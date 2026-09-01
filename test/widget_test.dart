// Smoke test for Part 1: verifies the app boots and renders today's prayer
// times computed by PrayerService. The calendar/notification sections talk
// to native plugins (device_calendar, flutter_local_notifications) that
// aren't available under flutter_test, so this deliberately doesn't assert
// on their state — a real device is required to exercise those.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/main.dart';

void main() {
  testWidgets('renders today\'s prayer times', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: PrayerLockoutApp()),
    );

    // Flush the FutureProvider microtask that computes today's timings,
    // then advance the fake clock past every staggered entrance animation's
    // Future.delayed so no timers are left pending at teardown.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Prayer times'), findsOneWidget);
    expect(find.text('Fajr'), findsOneWidget);
    expect(find.text('Dhuhr'), findsOneWidget);
    expect(find.text('Maghrib'), findsOneWidget);
  });
}
