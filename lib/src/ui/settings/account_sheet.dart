import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../components/components.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';

/// Sign in to sync, or create the account that syncs.
Future<void> showAccountSheet(BuildContext context) {
  return showStandardBottomSheet<void>(
    context,
    builder: (context) => const _AccountSheet(),
  );
}

class _AccountSheet extends ConsumerStatefulWidget {
  const _AccountSheet();

  @override
  ConsumerState<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<_AccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  /// False shows the sign-in form, true the sign-up one. One sheet rather
  /// than two, because the fields are identical and the only difference is
  /// which call it makes.
  bool _isSigningUp = false;

  /// A non-error message to show above the form, e.g. after a sign-up
  /// that still needs its email confirmed.
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final controller = ref.read(authControllerProvider.notifier);
    final email = _email.text.trim();
    final password = _password.text;

    final outcome = _isSigningUp
        ? await controller.signUp(email: email, password: password)
        : await controller.signIn(email: email, password: password);

    if (!mounted) return;

    switch (outcome) {
      case AuthOutcome.signedIn:
        Navigator.of(context).pop();
      case AuthOutcome.needsEmailConfirmation:
        // The account was created; it just has no session yet. Switching
        // the form back to sign-in is where they will need to be once the
        // link is clicked.
        setState(() {
          _isSigningUp = false;
          _notice = 'Account created. Click the link in the confirmation '
              'email, then sign in.';
        });
      case AuthOutcome.failed:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final auth = ref.watch(authControllerProvider);
    final busy = auth.isLoading;

    return StandardBottomSheet(
      title: _isSigningUp ? 'Create account' : 'Sign in',
      subtitle: _isSigningUp
          ? 'Your tasks, habits, study, chat and settings sync to every '
              'device you sign in on.'
          : 'Signing in merges this device with what your account already '
              'holds.',
      actions: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: 'Cancel',
              variant: ButtonVariant.outline,
              expand: true,
              onPressed: busy ? null : () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PrimaryButton(
              label: _isSigningUp ? 'Create' : 'Sign in',
              icon: PhLight.check,
              expand: true,
              loading: busy,
              onPressed: busy ? null : _submit,
            ),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (auth.hasError) ...[
              StatusCard(
                message: auth.error.toString(),
                tone: StatusTone.error,
              ),
              const SizedBox(height: 20),
            ] else if (_notice != null) ...[
              StatusCard(message: _notice!, tone: StatusTone.success),
              const SizedBox(height: 20),
            ],
            const FieldLabel(icon: PhLight.paperPlaneRight, label: 'Email'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              style: context.typography.ui(size: 14),
              decoration: appInputDecoration(context, hint: 'you@example.com'),
              validator: (value) {
                final email = value?.trim() ?? '';
                // Deliberately loose: the server is the real authority on
                // whether an address exists, and a strict pattern here
                // only ever rejects addresses that actually work.
                if (email.isEmpty) return 'Enter your email address.';
                if (!email.contains('@') || !email.contains('.')) {
                  return 'That does not look like an email address.';
                }
                return null;
              },
            ),
            const SizedBox(height: 22),
            const FieldLabel(icon: PhLight.lock, label: 'Password'),
            const SizedBox(height: 10),
            TextFormField(
              controller: _password,
              enabled: !busy,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => busy ? null : _submit(),
              style: context.typography.ui(size: 14),
              decoration: appInputDecoration(context, hint: '••••••••'),
              validator: (value) {
                final password = value ?? '';
                if (password.isEmpty) return 'Enter your password.';
                // Supabase's own default minimum. Checking it here turns a
                // round trip and a server error into an inline message.
                if (_isSigningUp && password.length < 6) {
                  return 'Use at least 6 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: busy
                  ? null
                  : () => setState(() {
                      _isSigningUp = !_isSigningUp;
                      _notice = null;
                    }),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                height: minTouchTarget,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _isSigningUp
                        ? 'Already have an account? Sign in'
                        : 'No account yet? Create one',
                    style: context.typography.ui(
                      size: 13,
                      color: palette.accent,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
