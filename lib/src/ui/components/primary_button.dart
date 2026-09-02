import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// How a [PrimaryButton] is filled.
enum ButtonVariant {
  /// Solid accent. One per surface — the single most likely action.
  filled,

  /// Glass fill with a hairline border. The default for secondary actions.
  outline,

  /// No fill or border. For tertiary actions inside dense rows.
  ghost,

  /// Solid danger. Deleting, clearing, revoking.
  danger,
}

enum ButtonSize { regular, compact }

/// The app's "island" CTA: a fully-rounded pill whose trailing icon sits in
/// its own circular chip rather than floating bare beside the label.
///
/// Pressing scales the whole pill down slightly and nudges the icon chip up
/// and to the right, so the control reads as having physical mass instead of
/// swapping color instantly.
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = ButtonVariant.filled,
    this.size = ButtonSize.regular,
    this.loading = false,
    this.expand = false,
  });

  final String label;

  /// Null disables the button, as does [loading].
  final VoidCallback? onPressed;

  /// Omit for a label-only pill; the icon chip is dropped with it.
  final IconData? icon;

  final ButtonVariant variant;
  final ButtonSize size;
  final bool loading;

  /// Fill the available width instead of hugging the label.
  final bool expand;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  bool get _isSolid =>
      widget.variant == ButtonVariant.filled ||
      widget.variant == ButtonVariant.danger;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final disabled = widget.onPressed == null || widget.loading;
    final compact = widget.size == ButtonSize.compact;

    final Color background;
    final Color foreground;
    final Color chipColor;
    Border? border;

    if (disabled) {
      background = palette.glassFill;
      foreground = palette.textMuted;
      chipColor = palette.glassBorder;
      border = widget.variant == ButtonVariant.ghost
          ? null
          : Border.all(color: palette.glassBorder);
    } else {
      switch (widget.variant) {
        case ButtonVariant.filled:
          background = palette.accent;
          foreground = palette.onAccent;
          chipColor = palette.onAccent.withValues(alpha: 0.15);
        case ButtonVariant.danger:
          background = palette.danger;
          foreground = palette.onAccent;
          chipColor = palette.onAccent.withValues(alpha: 0.18);
        case ButtonVariant.outline:
          background = palette.glassFill;
          foreground = palette.textPrimary;
          chipColor = palette.glassBorder;
          border = Border.all(color: palette.glassBorder);
        case ButtonVariant.ghost:
          background = Colors.transparent;
          foreground = palette.textSecondary;
          chipColor = palette.glassFill;
      }
    }

    final chipExtent = compact ? 28.0 : 34.0;
    final iconSize = compact ? 14.0 : 16.0;

    final pill = AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: AppMotion.fast,
      curve: AppMotion.spring,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.spring,
        padding: widget.icon == null
            ? EdgeInsets.symmetric(
                horizontal: compact ? 16 : 22,
                vertical: compact ? 10 : 14,
              )
            : EdgeInsets.only(
                left: compact ? 16 : 22,
                right: compact ? 5 : 6,
                top: compact ? 5 : 6,
                bottom: compact ? 5 : 6,
              ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: border,
          boxShadow: _isSolid && !disabled
              ? [
                  BoxShadow(
                    color: background.withValues(alpha: 0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: widget.icon == null
              ? MainAxisAlignment.center
              : MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.typography.ui(
                  size: compact ? 13 : 15,
                  weight: FontWeight.w600,
                  color: foreground,
                ),
              ),
            ),
            if (widget.icon != null || widget.loading) ...[
              const SizedBox(width: 14),
              AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.spring,
                width: chipExtent,
                height: chipExtent,
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
                        width: iconSize - 2,
                        height: iconSize - 2,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      )
                    : Icon(widget.icon, size: iconSize, color: foreground),
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: disabled ? null : (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: disabled ? null : widget.onPressed,
        child: widget.expand ? pill : IntrinsicWidth(child: pill),
      ),
    );
  }
}
