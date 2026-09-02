import 'package:flutter/material.dart';

import '../../../models/journal_entry.dart';
import '../../../models/journal_view.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

IconData iconForMood(JournalMood mood) {
  switch (mood) {
    case JournalMood.great:
      return PhLight.smiley;
    case JournalMood.good:
      return PhLight.smileyWink;
    case JournalMood.neutral:
      return PhLight.smileyMeh;
    case JournalMood.low:
      return PhLight.smileySad;
    case JournalMood.difficult:
      return PhLight.smileyNervous;
  }
}

/// Moods borrow existing semantic tokens rather than introducing five new
/// hues, so a monochrome theme stays monochrome: the ramp still reads
/// because the five glyphs differ, not because the colours do.
Color colorForMood(JournalMood mood, AppPalette palette) {
  switch (mood) {
    case JournalMood.great:
      return palette.success;
    case JournalMood.good:
      return palette.accent;
    case JournalMood.neutral:
      return palette.textMuted;
    case JournalMood.low:
      return palette.secondary;
    case JournalMood.difficult:
      return palette.danger;
  }
}

/// The five-step mood ramp, best to hardest.
class MoodPicker extends StatelessWidget {
  const MoodPicker({super.key, required this.selected, required this.onChanged});

  final JournalMood selected;
  final ValueChanged<JournalMood> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        for (final mood in orderedMoods) ...[
          Expanded(
            child: Semantics(
              button: true,
              selected: mood == selected,
              label: mood.label,
              child: GestureDetector(
                onTap: () => onChanged(mood),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.spring,
                  height: 68,
                  decoration: BoxDecoration(
                    color: mood == selected
                        ? colorForMood(mood, palette).withValues(alpha: 0.14)
                        : palette.glassFill,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: mood == selected
                          ? colorForMood(mood, palette)
                          : Colors.transparent,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        iconForMood(mood),
                        size: 22,
                        color: mood == selected
                            ? colorForMood(mood, palette)
                            : palette.textMuted,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        mood.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typography.ui(
                          size: 10,
                          weight: FontWeight.w600,
                          color: mood == selected
                              ? colorForMood(mood, palette)
                              : palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (mood != orderedMoods.last) const SizedBox(width: 7),
        ],
      ],
    );
  }
}

/// A single mood, for an entry card's corner.
class MoodGlyph extends StatelessWidget {
  const MoodGlyph({super.key, required this.mood, this.size = 34});

  final JournalMood mood;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = colorForMood(mood, context.palette);

    return Semantics(
      label: 'Mood: ${mood.label}',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(iconForMood(mood), size: size * 0.5, color: color),
      ),
    );
  }
}
