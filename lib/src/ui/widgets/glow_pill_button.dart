import 'package:flutter/material.dart';

import '../components/primary_button.dart';

/// The original name for the island CTA, kept so the Part 1 and Part 2
/// screens keep reading naturally. [PrimaryButton] is the component the
/// design system exposes and the one new code should reach for; this is a
/// thin adapter over it so both spell the same button.
class GlowPillButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return PrimaryButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      variant: filled ? ButtonVariant.filled : ButtonVariant.outline,
      loading: loading,
      expand: expand,
    );
  }
}
