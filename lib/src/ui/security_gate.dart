import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/security_providers.dart';
import 'theme/app_theme.dart';
import 'widgets/ambient_background.dart';
import 'widgets/lock_screen.dart';

/// Wraps the app root. Renders [child] when unlocked, [LockScreen] when
/// locked, and re-locks on every `paused` -> `resumed` lifecycle
/// transition (e.g. the user backgrounds the app and comes back), on top
/// of the cold-start lock [AppLockController.build] already applies.
class SecurityGate extends ConsumerStatefulWidget {
  const SecurityGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SecurityGate> createState() => _SecurityGateState();
}

class _SecurityGateState extends ConsumerState<SecurityGate>
    with WidgetsBindingObserver {
  AppLifecycleState? _previousState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_previousState == AppLifecycleState.paused &&
        state == AppLifecycleState.resumed) {
      ref.read(appLockControllerProvider.notifier).lockIfEnabled();
    }
    _previousState = state;
  }

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(appLockControllerProvider);

    return lockState.when(
      data: (state) => state.isLocked ? const LockScreen() : widget.child,
      loading: () => const _SecurityLoading(),
      error: (error, stackTrace) => _SecurityError(message: '$error'),
    );
  }
}

class _SecurityLoading extends StatelessWidget {
  const _SecurityLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: Center(
          child: CircularProgressIndicator(color: context.palette.accent, strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _SecurityError extends StatelessWidget {
  const _SecurityError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Security check failed:\n$message',
                textAlign: TextAlign.center,
                style: context.typography.ui(color: context.palette.danger),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
