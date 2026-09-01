// Smoke test: verifies the app boots past the security gate and renders
// today's prayer times computed by PrayerService. The calendar/
// notification/biometric/Hive layers all talk to native plugins that
// aren't available under flutter_test, so this deliberately doesn't assert
// on their state — a real device is required to exercise those.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cotv/main.dart';
import 'package:cotv/src/providers/security_providers.dart';
import 'package:cotv/src/security/security_service.dart';

/// Avoids touching the real `flutter_secure_storage` platform channel
/// (unavailable under `flutter_test`) by always reporting biometrics as
/// disabled, which is enough for [AppLockController.build] to resolve to
/// [AppLockStatus.unlocked] without any plugin call.
class _FakeSecurityService extends SecurityService {
  @override
  Future<bool> isBiometricEnabled() async => false;
}

void main() {
  testWidgets('renders today\'s prayer times', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          securityServiceProvider.overrideWithValue(_FakeSecurityService()),
        ],
        child: const PrayerLockoutApp(),
      ),
    );

    // Flush the AppLockController/FutureProvider microtasks, then advance
    // the fake clock past every staggered entrance animation's
    // Future.delayed so no timers are left pending at teardown.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Prayer times'), findsOneWidget);
    expect(find.text('Fajr'), findsOneWidget);
    expect(find.text('Dhuhr'), findsOneWidget);
    expect(find.text('Maghrib'), findsOneWidget);
  });
}
