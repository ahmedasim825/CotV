import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/security_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/user_settings_providers.dart';
import '../../security/security_service.dart';
import '../../services/prayer_service.dart';
import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'calculation_labels.dart';
import 'location_sheet.dart';
import 'option_picker_sheet.dart';
import 'widgets/settings_row.dart';
import 'widgets/theme_picker.dart';

/// Appearance, security, location and prayer-calculation preferences.
///
/// Appearance and security are fully live. Location persists to
/// [UserSettings] and feeds the live calculation; the calculation method,
/// madhab and lockout window drive the in-memory providers now and gain
/// their own persistence in Part 4, which is stated on the screen rather
/// than left for the user to discover.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdaptiveLayout(
      builder: (context, windowSize) {
        final padding = windowSize.pagePadding;

        return ListView(
          padding: EdgeInsets.fromLTRB(
            padding,
            12,
            padding,
            40 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const SectionHeader(eyebrow: 'PREFERENCES', title: 'Settings'),
            const SizedBox(height: 32),
            const SectionHeader(
              eyebrow: 'APPEARANCE',
              title: 'Theme',
              titleSize: 22,
              subtitle: 'Changes every surface in the app immediately.',
            ),
            const SizedBox(height: 16),
            ThemePicker(columns: windowSize.isCompact ? 2 : 3),
            const SizedBox(height: 36),
            const SectionHeader(
              eyebrow: 'SECURITY',
              title: 'App lock',
              titleSize: 22,
            ),
            const SizedBox(height: 16),
            const _SecuritySection(),
            const SizedBox(height: 36),
            const SectionHeader(
              eyebrow: 'LOCATION',
              title: 'Where you are',
              titleSize: 22,
            ),
            const SizedBox(height: 16),
            const _LocationSection(),
            const SizedBox(height: 36),
            const SectionHeader(
              eyebrow: 'CALCULATION',
              title: 'Prayer times',
              titleSize: 22,
            ),
            const SizedBox(height: 16),
            const _CalculationSection(),
            const SizedBox(height: 28),
            const _PrivacyNote(),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Security
// ---------------------------------------------------------------------------

/// The app-lock switch, wired straight to [SecurityService] (which owns the
/// `flutter_secure_storage` copy of the preference) through
/// [AppLockController].
///
/// Turning the lock *on* runs the biometric challenge first and only
/// persists once it succeeds — otherwise a user with no working Face ID
/// could switch on a lock they cannot pass, and the next launch would shut
/// them out of their own data.
class _SecuritySection extends ConsumerStatefulWidget {
  const _SecuritySection();

  @override
  ConsumerState<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends ConsumerState<_SecuritySection>
    with WidgetsBindingObserver {
  bool _isBusy = false;
  String? _errorMessage;

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
    // The user may have just come back from enrolling Face ID in iOS
    // Settings, so what the device can do has to be re-read rather than
    // trusted from launch.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(biometricCapabilityProvider);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _isBusy = true;
      _errorMessage = null;
    });

    try {
      if (enabled) {
        final passed = await ref.read(securityServiceProvider).authenticate(
              reason: 'Confirm to turn on app lock',
            );
        // A cancel is not an error — leave the switch as it was.
        if (!passed) return;
      }
      await ref
          .read(appLockControllerProvider.notifier)
          .setBiometricEnabled(enabled);
    } on SecurityException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lockAsync = ref.watch(appLockControllerProvider);
    final capabilityAsync = ref.watch(biometricCapabilityProvider);

    final isEnabled = lockAsync.value?.biometricEnabled ?? false;
    final capability = capabilityAsync.value;
    final canUseLock = capability?.deviceSupported ?? false;
    final isResolving = capabilityAsync.isLoading || lockAsync.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          children: [
            SettingsToggleRow(
              icon: isEnabled ? PhLight.lock : PhLight.lockKeyOpen,
              title: 'Require ${capability?.label ?? 'authentication'}',
              subtitle: capability?.description ??
                  'Checking what this device supports…',
              value: isEnabled,
              enabled: canUseLock && !_isBusy,
              busy: _isBusy || isResolving,
              onChanged: _setEnabled,
            ),
            SettingsRow(
              icon: PhLight.shieldCheck,
              title: 'Lock now',
              subtitle: isEnabled
                  ? 'Return to the lock screen straight away.'
                  : 'Turn app lock on to use this.',
              enabled: isEnabled && !_isBusy,
              iconTint: palette.textMuted,
              trailing: Icon(
                PhLight.caretRight,
                size: 13,
                color: palette.textMuted,
              ),
              onTap: () =>
                  ref.read(appLockControllerProvider.notifier).lockIfEnabled(),
            ),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          StatusCard(message: _errorMessage!, tone: StatusTone.error),
        ],
        if (capabilityAsync.hasError) ...[
          const SizedBox(height: 12),
          StatusCard(
            message: 'Could not read this device\'s security capabilities: '
                '${capabilityAsync.error}',
            tone: StatusTone.error,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Location
// ---------------------------------------------------------------------------

class _LocationSection extends ConsumerWidget {
  const _LocationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsControllerProvider).value;
    final hasLocation = settings?.hasLocation ?? false;
    final fallback = PrayerService.fallbackCoordinates;

    final latitude = settings?.latitude ?? fallback.latitude;
    final longitude = settings?.longitude ?? fallback.longitude;

    return SettingsGroup(
      children: [
        SettingsValueRow(
          icon: PhLight.mapPin,
          title: 'Coordinates',
          subtitle: hasLocation
              ? 'Saved on this device.'
              : 'Using the Cairo fallback until a location is set.',
          value: '${latitude.toStringAsFixed(4)}, '
              '${longitude.toStringAsFixed(4)}',
          onTap: () => showLocationSheet(context),
        ),
        const SettingsRow(
          icon: PhLight.globeHemisphereEast,
          title: 'Automatic location',
          subtitle: 'Device GPS and permission handling arrive in Part 4.',
          enabled: false,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Calculation
// ---------------------------------------------------------------------------

class _CalculationSection extends ConsumerWidget {
  const _CalculationSection();

  static const List<int> _lockoutMinutes = [10, 15, 20, 30, 45, 60];
  static const List<int> _preAdhanMinutes = [0, 5, 10, 15, 20, 30];

  String _minutesLabel(int minutes) =>
      minutes == 0 ? 'Off' : '$minutes minutes';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final method = ref.watch(calculationMethodProvider);
    final madhab = ref.watch(madhabProvider);
    final lockout = ref.watch(lockoutDurationProvider);
    final settings = ref.watch(userSettingsControllerProvider).value;
    final preAdhan = settings?.preAdhanNotificationMinutes ?? 15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          children: [
            SettingsValueRow(
              icon: PhLight.compass,
              title: 'Calculation method',
              subtitle: calculationMethodNote(method),
              value: calculationMethodLabel(method),
              onTap: () async {
                final picked = await showOptionPicker<CalculationMethod>(
                  context,
                  title: 'Calculation method',
                  subtitle: 'Each authority uses different solar angles for '
                      'Fajr and Isha.',
                  selected: method,
                  options: [
                    for (final value in CalculationMethod.values)
                      PickerOption(
                        value: value,
                        label: calculationMethodLabel(value),
                        note: calculationMethodNote(value),
                      ),
                  ],
                );
                if (picked != null) {
                  ref.read(calculationMethodProvider.notifier).set(picked);
                }
              },
            ),
            SettingsValueRow(
              icon: PhLight.sunHorizon,
              title: 'Madhab',
              subtitle: madhabNote(madhab),
              value: madhabLabel(madhab),
              onTap: () async {
                final picked = await showOptionPicker<Madhab>(
                  context,
                  title: 'Madhab',
                  subtitle: 'Only affects when Asr begins.',
                  selected: madhab,
                  options: [
                    for (final value in Madhab.values)
                      PickerOption(
                        value: value,
                        label: madhabLabel(value),
                        note: madhabNote(value),
                      ),
                  ],
                );
                if (picked != null) {
                  ref.read(madhabProvider.notifier).set(picked);
                }
              },
            ),
            SettingsValueRow(
              icon: PhLight.timer,
              title: 'Lockout window',
              subtitle: 'How long each prayer stays blocked out after the '
                  'Adhan.',
              value: '${lockout.inMinutes} minutes',
              onTap: () async {
                final picked = await showOptionPicker<int>(
                  context,
                  title: 'Lockout window',
                  subtitle: 'Applies to every prayer except Fajr, which '
                      'runs to sunrise.',
                  selected: lockout.inMinutes,
                  options: [
                    for (final minutes in _lockoutMinutes)
                      PickerOption(
                        value: minutes,
                        label: '$minutes minutes',
                      ),
                  ],
                );
                if (picked != null) {
                  ref
                      .read(lockoutDurationProvider.notifier)
                      .set(Duration(minutes: picked));
                }
              },
            ),
            SettingsValueRow(
              icon: PhLight.bellSimple,
              title: 'Pre-Adhan reminder',
              subtitle: 'A heads-up before each prayer begins.',
              value: _minutesLabel(preAdhan),
              onTap: () async {
                final picked = await showOptionPicker<int>(
                  context,
                  title: 'Pre-Adhan reminder',
                  subtitle: 'Set to Off for Adhan-time notifications only.',
                  selected: preAdhan,
                  options: [
                    for (final minutes in _preAdhanMinutes)
                      PickerOption(
                        value: minutes,
                        label: _minutesLabel(minutes),
                        note: minutes == 0
                            ? 'No advance warning'
                            : '$minutes minutes before the Adhan',
                      ),
                  ],
                );
                if (picked == null) return;

                // Persisted, and mirrored into the provider the notification
                // scheduler reads so the change applies without a restart.
                await ref
                    .read(userSettingsControllerProvider.notifier)
                    .setPreAdhanMinutes(picked);
                ref
                    .read(preAdhanOffsetProvider.notifier)
                    .set(Duration(minutes: picked));
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(PhLight.info, size: 14, color: palette.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Method, madhab and lockout window apply to this session. '
                'Saving them across launches lands in Part 4 alongside '
                'automatic location.',
                style: context.typography.ui(
                  size: 11.5,
                  color: palette.textMuted,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return CustomCard(
      elevated: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhLight.shieldCheck, size: 16, color: palette.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Tasks, habits, journal entries and settings are stored only '
              'on this device. The app-lock preference lives in the '
              'system keychain.',
              style: context.typography.ui(
                size: 12,
                color: palette.textMuted,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
