import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// An "island" CTA: a fully-rounded pill with a trailing icon nested in its
/// own circular chip (never a bare icon glyph floating next to the label).
/// Pressing scales the whole pill down slightly and nudges the icon chip up
/// and to the right, simulating physical mass rather than an instant color
/// swap.
class GlowPillButton extends StatefulWidget {
  const GlowPillButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = true,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final bool loading;
  final bool expand;

  @override
  State<GlowPillButton> createState() => _GlowPillButtonState();
}

class _GlowPillButtonState extends State<GlowPillButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null || widget.loading;
    final labelColor = widget.filled && !disabled
        ? AppPalette.onAmber
        : AppPalette.textPrimary;
    final chipColor = widget.filled && !disabled
        ? const Color(0x261D1408)
        : AppPalette.glassBorder;

    final pill = AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: AppMotion.fast,
      curve: AppMotion.spring,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.spring,
        padding: const EdgeInsets.only(left: 22, right: 6, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: disabled
              ? AppPalette.glassFill
              : (widget.filled ? AppPalette.amber : AppPalette.glassFill),
          borderRadius: BorderRadius.circular(999),
          border: widget.filled ? null : Border.all(color: AppPalette.glassBorder),
        ),
        child: Row(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                widget.label,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.ui(weight: FontWeight.w600, color: labelColor),
              ),
            ),
            const SizedBox(width: 14),
            AnimatedContainer(
              duration: AppMotion.fast,
              curve: AppMotion.spring,
              width: 34,
              height: 34,
              alignment: Alignment.center,
              transform: _pressed
                  ? (Matrix4.identity()
                    ..translateByDouble(1.5, -1.5, 0.0, 1.0)
                    ..scaleByDouble(1.06, 1.06, 1.06, 1.0))
                  : Matrix4.identity(),
              transformAlignment: Alignment.center,
              decoration: BoxDecoration(color: chipColor, shape: BoxShape.circle),
              child: widget.loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: labelColor),
                    )
                  : Icon(widget.icon, size: 16, color: labelColor),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onTapDown: disabled ? null : (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: disabled ? null : widget.onPressed,
      child: widget.expand ? pill : IntrinsicWidth(child: pill),
    );
  }
}
