import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../models/food_models.dart';
import '../../../providers/nutrition_providers.dart';
import '../../../services/nutritionix_service.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import '../../widgets/status_card.dart';

/// Where a camera is actually available.
///
/// `mobile_scanner` 7.4 ships implementations for Android, iOS, macOS and
/// web only — there is none for Windows, and constructing a controller
/// there fails at runtime rather than at compile time. Off those platforms
/// the sheet asks for the barcode number instead, which also makes the
/// whole flow testable on a desktop with no camera.
bool get barcodeCameraSupported =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Scans (or asks for) a barcode and resolves it against Nutritionix.
///
/// Returns the food once the lookup succeeds, or null if the sheet was
/// dismissed. The caller decides what to do with it — the search screen
/// opens the serving configurator.
Future<FoodItem?> showBarcodeScannerSheet(BuildContext context) {
  return showStandardBottomSheet<FoodItem>(
    context,
    builder: (context) => const _BarcodeScannerSheet(),
  );
}

class _BarcodeScannerSheet extends ConsumerStatefulWidget {
  const _BarcodeScannerSheet();

  @override
  ConsumerState<_BarcodeScannerSheet> createState() =>
      _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends ConsumerState<_BarcodeScannerSheet> {
  /// Real UPCs that resolve against the public database, so the desktop
  /// path can be exercised without hunting for a barcode to type in.
  static const List<({String upc, String label})> _samples = [
    (upc: '049000006346', label: 'Coca-Cola 12oz'),
    (upc: '038000138416', label: "Kellogg's Corn Flakes"),
    (upc: '028400047685', label: 'Doritos Nacho Cheese'),
  ];

  final TextEditingController _upcController = TextEditingController();

  MobileScannerController? _scanner;
  bool _isLookingUp = false;
  String? _error;

  /// Latched on the first barcode the camera reports. A continuous scanner
  /// fires for every frame the code stays in view, so without this the
  /// lookup would be issued dozens of times for one scan.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    if (barcodeCameraSupported) {
      _scanner = MobileScannerController(
        // Only the linear symbologies a packaged food carries, so a QR
        // code in the frame does not resolve to a nonsense lookup.
        formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE],
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    }
  }

  @override
  void dispose() {
    _upcController.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .firstWhere((value) => value != null && value.isNotEmpty,
            orElse: () => null);
    if (code == null) return;

    _handled = true;
    _lookUp(code);
  }

  Future<void> _lookUp(String upc) async {
    setState(() {
      _isLookingUp = true;
      _error = null;
    });

    // Stop the camera before the round trip, so the preview is not still
    // scanning behind a sheet that has already committed to one code.
    await _scanner?.stop();

    try {
      final food =
          await ref.read(nutritionixServiceProvider).getFoodByBarcode(upc);
      if (!mounted) return;
      Navigator.of(context).pop(food);
    } on NutritionixException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _error = error.message;
        // Let the user try another code rather than stranding the sheet.
        _handled = false;
      });
      await _scanner?.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = barcodeCameraSupported;

    return StandardBottomSheet(
      title: 'Scan barcode',
      subtitle: camera
          ? 'Point the camera at the barcode on the package.'
          : 'No camera on this platform — type the barcode number from the '
              'package instead.',
      heightFactor: camera ? 0.8 : 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (camera) _cameraView() else _manualEntry(),
          if (_error != null) ...[
            const SizedBox(height: 18),
            StatusCard(message: _error!, tone: StatusTone.error),
          ],
          if (_isLookingUp) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.palette.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Looking this up…',
                  style: context.typography.ui(
                    size: 13,
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cameraView() {
    final palette = context.palette;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _scanner!,
              onDetect: _onDetect,
              // The plugin's own fallback is a black box with a white
              // Material error glyph, which is the one surface in the app
              // that would ignore the theme. A denied camera permission is
              // the common way to land here.
              errorBuilder: (context, error) => ColoredBox(
                color: palette.surfaceRaised,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      error.errorDetails?.message ??
                          'The camera is unavailable. Check camera access '
                              'for Milo in system settings.',
                      textAlign: TextAlign.center,
                      style: context.typography.ui(
                        size: 13,
                        color: palette.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // A frame rather than a full-bleed preview, so it is obvious
            // where the barcode has to sit.
            Center(
              child: FractionallySizedBox(
                widthFactor: 0.78,
                heightFactor: 0.34,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: palette.accentBright, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _manualEntry() {
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel(icon: PhLight.barcode, label: 'Barcode number'),
        const SizedBox(height: 10),
        TextField(
          controller: _upcController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textInputAction: TextInputAction.go,
          enabled: !_isLookingUp,
          onSubmitted: _lookUp,
          decoration: appInputDecoration(
            context,
            hint: '049000006346',
            prefixIcon: Icon(PhLight.barcode, size: 17, color: palette.textMuted),
          ),
          style: context.typography.mono(size: 15),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Look up',
          icon: PhLight.magnifyingGlass,
          expand: true,
          loading: _isLookingUp,
          onPressed: () => _lookUp(_upcController.text),
        ),
        const SizedBox(height: 22),
        Text(
          'TRY ONE OF THESE',
          style: context.typography.eyebrow(color: palette.textMuted),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sample in _samples)
              _SampleChip(
                label: sample.label,
                onTap: _isLookingUp
                    ? null
                    : () {
                        _upcController.text = sample.upc;
                        _lookUp(sample.upc);
                      },
              ),
          ],
        ),
      ],
    );
  }
}

class _SampleChip extends StatelessWidget {
  const _SampleChip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Sample barcode, $label',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: palette.glassFill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: palette.glassBorder),
          ),
          child: Text(
            label,
            style: context.typography.ui(size: 12.5, color: palette.textSecondary),
          ),
        ),
      ),
    );
  }
}
