import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_providers.dart';
import '../../providers/user_settings_providers.dart';
import '../../services/prayer_service.dart';
import '../components/components.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

/// Manual coordinate entry.
///
/// The coordinates saved here are what every prayer time, lockout window and
/// notification is calculated from; without them the app falls back to Cairo.
/// This is also the path for anyone who would rather not grant a location
/// permission at all.
Future<void> showLocationSheet(BuildContext context) {
  return showStandardBottomSheet<void>(
    context,
    builder: (_) => const LocationSheet(),
  );
}

class LocationSheet extends ConsumerStatefulWidget {
  const LocationSheet({super.key});

  @override
  ConsumerState<LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends ConsumerState<LocationSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(userSettingsRepositoryProvider).get();
    _latitudeController =
        TextEditingController(text: settings.latitude?.toString() ?? '');
    _longitudeController =
        TextEditingController(text: settings.longitude?.toString() ?? '');
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  String? _validate(String? raw, {required double limit, required String name}) {
    final value = double.tryParse((raw ?? '').trim());
    if (value == null) return 'Enter a $name in decimal degrees.';
    if (value < -limit || value > limit) {
      return '$name must be between -$limit and $limit.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final latitude = double.parse(_latitudeController.text.trim());
    final longitude = double.parse(_longitudeController.text.trim());

    // Persisted for next launch, and pushed into the live calculation so
    // the prayer times on screen update without a restart.
    await ref
        .read(userSettingsControllerProvider.notifier)
        .setLocation(latitude: latitude, longitude: longitude);
    ref
        .read(prayerCoordinatesProvider.notifier)
        .set(Coordinates(latitude, longitude));

    if (mounted) Navigator.of(context).pop();
  }

  void _useFallback() {
    final fallback = PrayerService.fallbackCoordinates;
    _latitudeController.text = fallback.latitude.toString();
    _longitudeController.text = fallback.longitude.toString();
    _formKey.currentState?.validate();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Form(
      key: _formKey,
      child: StandardBottomSheet(
        title: 'Location',
        subtitle: 'Prayer times are calculated from these coordinates. '
            'Decimal degrees — north and east are positive.',
        heightFactor: 0.75,
        actions: Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: 'Cancel',
                icon: PhLight.x,
                variant: ButtonVariant.outline,
                expand: true,
                onPressed:
                    _isSaving ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                label: 'Save',
                icon: PhLight.check,
                expand: true,
                loading: _isSaving,
                onPressed: _isSaving ? null : _save,
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FieldLabel(icon: PhLight.mapPin, label: 'Latitude'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _latitudeController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              style: context.typography.mono(size: 15, color: palette.textPrimary),
              decoration: appInputDecoration(context, hint: '30.0444'),
              validator: (value) =>
                  _validate(value, limit: 90, name: 'latitude'),
            ),
            const SizedBox(height: 20),
            const FieldLabel(icon: PhLight.mapPin, label: 'Longitude'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _longitudeController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              style: context.typography.mono(size: 15, color: palette.textPrimary),
              decoration: appInputDecoration(context, hint: '31.2357'),
              validator: (value) =>
                  _validate(value, limit: 180, name: 'longitude'),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Use default (Cairo)',
              icon: PhLight.crosshairSimple,
              variant: ButtonVariant.outline,
              size: ButtonSize.compact,
              onPressed: _isSaving ? null : _useFallback,
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: palette.glassFill,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: palette.glassBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(PhLight.info, size: 15, color: palette.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'These coordinates drive every prayer time, lockout '
                      'window and notification. Entering them by hand is '
                      'currently the only way off the Cairo default.',
                      style: context.typography.ui(
                        size: 11.5,
                        color: palette.textMuted,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
