import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/security_providers.dart';
import '../theme/app_theme.dart';
import 'ambient_background.dart';
import 'glass_shell.dart';
import '../components/components.dart';
import 'ph_light_icons.dart';

/// Full-screen biometric challenge shown whenever [AppLockState.isLocked]
/// is true. Attempts authentication automatically once on appearance, and
/// always offers a manual retry button (auto-prompt can be dismissed by
/// the OS, or fail silently on some devices).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appLockControllerProvider.notifier).unlock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final lockState = ref.watch(appLockControllerProvider);
    final isAuthenticating = lockState.isLoading;
    final errorMessage = lockState.value?.errorMessage;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AmbientBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: GlassShell(
                outerRadius: 36,
                padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.palette.accentSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        PhLight.lock,
                        size: 28,
                        color: context.palette.accentBright,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Milo is locked',
                      textAlign: TextAlign.center,
                      style: context.typography.display(size: 24, weight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Use Face ID, Touch ID, or your device passcode to '
                      'continue.',
                      textAlign: TextAlign.center,
                      style: context.typography.ui(
                        size: 13.5,
                        color: context.palette.textMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    PrimaryButton(
                      label: isAuthenticating ? 'Authenticating…' : 'Unlock',
                      icon: PhLight.fingerprint,
                      loading: isAuthenticating,
                      onPressed: isAuthenticating
                          ? null
                          : () => ref
                              .read(appLockControllerProvider.notifier)
                              .unlock(),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 18),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            PhLight.warningCircle,
                            size: 16,
                            color: context.palette.danger,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              errorMessage,
                              style: context.typography.ui(
                                size: 12.5,
                                color: context.palette.danger,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
