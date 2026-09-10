import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/nutrition_providers.dart';
import '../../providers/security_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/user_settings_providers.dart';
import '../../security/security_service.dart';
import '../../services/prayer_service.dart';
import '../../services/shortcuts_service.dart';
import '../../services/supabase_config.dart';
import '../components/components.dart';
import '../responsive/breakpoints.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'account_sheet.dart';
import 'calculation_labels.dart';
import 'location_sheet.dart';
import 'nutrition_targets_sheet.dart';
import 'option_picker_sheet.dart';
import 'widgets/settings_row.dart';

/// Appearance, security, location and prayer-calculation preferences.
///
/// Appearance and security are fully live. Location persists to
/// [UserSettings] and feeds the live calculation; the calculation method
/// and madhab drive the in-memory providers now and gain their own
/// persistence in Part 4, which is stated on the screen rather than left
/// for the user to discover.
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
              eyebrow: 'NUTRITION',
              title: 'Daily targets',
              titleSize: 22,
              subtitle: 'What the dashboard measures the day against.',
            ),
            const SizedBox(height: 16),
            const _NutritionTargetsSection(),
            const SizedBox(height: 36),
            const SectionHeader(
              eyebrow: 'SYNC',
              title: 'Account',
              titleSize: 22,
              subtitle: 'Sign in to carry your food log between devices.',
            ),
            const SizedBox(height: 16),
            const _AccountSection(),
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
            if (ShortcutsService.isSupported) ...[
              const SizedBox(height: 36),
              const SectionHeader(
                eyebrow: 'AUTOMATION',
                title: 'Shortcuts',
                titleSize: 22,
                subtitle: 'Study timers can be started by Siri or from a '
                    'Shortcuts automation.',
              ),
              const SizedBox(height: 16),
              const _ShortcutsSection(),
            ],
            const SizedBox(height: 28),
            const _PrivacyNote(),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Nutrition targets
// ---------------------------------------------------------------------------

/// The four daily goals, each row opening the same editing sheet.
///
/// A row whose value has never been set says so, rather than presenting
/// the fallback as if it were a choice the user made.
class _NutritionTargetsSection extends ConsumerWidget {
  const _NutritionTargetsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final targets = ref.watch(nutritionTargetsProvider);
    final settings = ref.watch(userSettingsControllerProvider).value;

    Widget row({
      required IconData icon,
      required String title,
      required int value,
      required String unit,
      required bool isConfigured,
    }) {
      return SettingsRow(
        icon: icon,
        title: title,
        subtitle: isConfigured ? null : 'Default',
        onTap: () => showNutritionTargetsSheet(context),
        trailing: Text(
          '$value $unit',
          style: context.typography.ui(
            size: 14,
            weight: FontWeight.w600,
            color: isConfigured ? palette.textPrimary : palette.textMuted,
          ),
        ),
      );
    }

    return SettingsGroup(
      children: [
        row(
          icon: PhLight.fire,
          title: 'Calories',
          value: targets.calories,
          unit: 'kcal',
          isConfigured: settings?.dailyCalorieTarget != null,
        ),
        row(
          icon: PhLight.bowlFood,
          title: 'Protein',
          value: targets.protein,
          unit: 'g',
          isConfigured: settings?.proteinTargetGrams != null,
        ),
        row(
          icon: PhLight.bowlFood,
          title: 'Carbs',
          value: targets.carbs,
          unit: 'g',
          isConfigured: settings?.carbTargetGrams != null,
        ),
        row(
          icon: PhLight.drop,
          title: 'Fat',
          value: targets.fat,
          unit: 'g',
          isConfigured: settings?.fatTargetGrams != null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shortcuts
// ---------------------------------------------------------------------------

/// The way into the Shortcuts app, where the study App Intents this build
/// registers show up as actions.
///
/// It only opens Shortcuts. iOS has no public scheme for creating a
/// shortcut on the user's behalf, so the row says what it does rather than
/// implying it will build one.
/// Who is signed in, and the control to change that.
///
/// The whole food logger works signed out — this section is the difference
/// between a log that lives on this device and one that follows the
/// account, so it says which of those is currently true rather than
/// implying sync is required.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final user = ref.watch(currentUserProvider);
    final configured = SupabaseConfig.isConfigured;
    final syncError = ref.watch(syncErrorProvider);

    if (!configured) {
      return const SettingsGroup(
        children: [
          SettingsRow(
            icon: PhLight.wifiSlash,
            title: 'Sync not set up in this build',
            subtitle:
                'Rebuild with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY to '
                'enable it. The food log works without it, on this device.',
            enabled: false,
          ),
        ],
      );
    }

    return Column(
      children: [
        if (syncError != null) ...[
          StatusCard(message: syncError, tone: StatusTone.error),
          const SizedBox(height: 16),
        ],
        SettingsGroup(
          children: [
            SettingsRow(
              icon: user == null ? PhLight.lockKeyOpen : PhLight.checkCircle,
              title: user == null ? 'Not signed in' : 'Signed in',
              subtitle: user == null
                  ? 'Your food log and recipes stay on this device.'
                  : user.email ?? 'Syncing to your account.',
              iconTint: user == null ? palette.textMuted : palette.success,
              trailing: Icon(
                PhLight.caretRight,
                size: 13,
                color: palette.textMuted,
              ),
              onTap: user == null
                  ? () => showAccountSheet(context)
                  : () => _confirmSignOut(context, ref),
            ),
            if (user != null)
              SettingsRow(
                icon: PhLight.arrowClockwise,
                title: 'Refresh now',
                subtitle: 'Pull the log and recipes from the server again.',
                iconTint: palette.textMuted,
                onTap: () {
                  ref.read(dailyNutritionProvider.notifier).refresh();
                  ref.read(customRecipeListProvider.notifier).refresh();
                },
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Sign out?',
      message: 'Your food log stays on the server. This device drops back '
          'to a local-only log until you sign in again.',
      confirmLabel: 'Sign out',
    );
    if (confirmed) await ref.read(authControllerProvider.notifier).signOut();
  }
}

class _ShortcutsSection extends StatefulWidget {
  const _ShortcutsSection();

  @override
  State<_ShortcutsSection> createState() => _ShortcutsSectionState();
}

class _ShortcutsSectionState extends State<_ShortcutsSection> {
  static const ShortcutsService _service = ShortcutsService();

  bool _failed = false;

  Future<void> _open() async {
    final opened = await _service.open();
    if (mounted) setState(() => _failed = !opened);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsGroup(
          children: [
            SettingsRow(
              icon: PhLight.lightning,
              title: 'Open Shortcuts',
              subtitle: '"Start Study Timer" and "Stop Study Timer" appear '
                  'as actions once this app has been opened at least once.',
              iconTint: palette.textMuted,
              trailing: Icon(
                PhLight.caretRight,
                size: 13,
                color: palette.textMuted,
              ),
              onTap: _open,
            ),
          ],
        ),
        if (_failed) ...[
          const SizedBox(height: 12),
          const StatusCard(
            message: 'Could not open Shortcuts. It may have been removed '
                'from this device.',
            tone: StatusTone.error,
          ),
        ],
      ],
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

  static const List<int> _preAdhanMinutes = [0, 5, 10, 15, 20, 30];

  String _minutesLabel(int minutes) =>
      minutes == 0 ? 'Off' : '$minutes minutes';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final method = ref.watch(calculationMethodProvider);
    final madhab = ref.watch(madhabProvider);
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
              'Tasks, habits, study logs and settings are stored only '
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
