import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/habit.dart';
import '../../models/habit_view.dart';
import '../../providers/habit_providers.dart';
import '../components/components.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import 'habit_colors.dart';

const _uuid = Uuid();

/// Opens the create/edit habit sheet. Pass [existing] to edit, omit it to
/// create.
///
/// Resolves to the saved [Habit], or null if the sheet was dismissed or the
/// habit was deleted.
Future<Habit?> showHabitFormSheet(BuildContext context, {Habit? existing}) {
  return showStandardBottomSheet<Habit>(
    context,
    builder: (_) => HabitFormSheet(existing: existing),
  );
}

/// Bottom-sheet form for creating and editing a [Habit].
class HabitFormSheet extends ConsumerStatefulWidget {
  const HabitFormSheet({super.key, this.existing});

  final Habit? existing;

  @override
  ConsumerState<HabitFormSheet> createState() => _HabitFormSheetState();
}

class _HabitFormSheetState extends ConsumerState<HabitFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;

  late HabitFrequency _frequency;
  late String _colorHex;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _frequency = existing?.frequency ?? HabitFrequency.daily;
    _colorHex = existing?.colorHex ?? habitColorHexes.first;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final title = _titleController.text.trim();
    final existing = widget.existing;
    final notifier = ref.read(habitListProvider.notifier);

    final Habit saved;
    if (existing == null) {
      saved = Habit(
        id: _uuid.v4(),
        title: title,
        frequency: _frequency,
        colorHex: _colorHex,
      );
      await notifier.addHabit(saved);
    } else {
      // Completions and the streak are the repository's to maintain; the
      // form only ever edits what the user typed.
      saved = existing.copyWith(
        title: title,
        frequency: _frequency,
        colorHex: _colorHex,
      );
      await notifier.updateHabit(saved);
    }

    if (mounted) Navigator.of(context).pop(saved);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final confirmed = await confirmDestructive(
      context,
      title: 'Delete habit?',
      message: 'Removing "${existing.title}" also removes its '
          '${existing.completedDates.length} recorded '
          '${existing.completedDates.length == 1 ? 'completion' : 'completions'} '
          'and its streak. This cannot be undone.',
      confirmIcon: PhLight.trash,
    );
    if (!confirmed || !mounted) return;

    await ref.read(habitListProvider.notifier).deleteHabit(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Form(
      key: _formKey,
      child: StandardBottomSheet(
        title: _isEditing ? 'Edit habit' : 'New habit',
        heightFactor: 0.8,
        trailing: _isEditing
            ? _IconAction(
                icon: PhLight.trash,
                tint: palette.danger,
                semanticLabel: 'Delete habit',
                onTap: _isSaving ? null : _delete,
              )
            : null,
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
                label: _isEditing ? 'Save' : 'Add habit',
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
            const FieldLabel(icon: PhLight.target, label: 'Habit'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleController,
              autofocus: !_isEditing,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              style: context.typography.ui(size: 15),
              decoration: appInputDecoration(
                context,
                hint: 'What do you want to keep up?',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Give the habit a name.'
                  : null,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 22),
            const FieldLabel(icon: PhLight.repeat, label: 'Frequency'),
            const SizedBox(height: 10),
            _FrequencySelector(
              selected: _frequency,
              onChanged: (value) => setState(() => _frequency = value),
            ),
            const SizedBox(height: 22),
            const FieldLabel(icon: PhLight.swatches, label: 'Colour'),
            const SizedBox(height: 12),
            _ColorSelector(
              selected: _colorHex,
              onChanged: (value) => setState(() => _colorHex = value),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 22),
              _StreakNote(habit: widget.existing!),
            ],
          ],
        ),
      ),
    );
  }
}

class _FrequencySelector extends StatelessWidget {
  const _FrequencySelector({required this.selected, required this.onChanged});

  final HabitFrequency selected;
  final ValueChanged<HabitFrequency> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Row(
      children: [
        for (final frequency in HabitFrequency.values) ...[
          Expanded(
            child: Semantics(
              button: true,
              selected: frequency == selected,
              label: frequency.label,
              child: GestureDetector(
                onTap: () => onChanged(frequency),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: context.motion.fast,
                  curve: AppMotion.spring,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: frequency == selected
                        ? palette.accentSoft
                        : palette.glassFill,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: frequency == selected
                          ? palette.accent
                          : palette.glassBorder,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        frequency.label,
                        style: context.typography.ui(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: frequency == selected
                              ? palette.accent
                              : palette.textSecondary,
                        ),
                      ),
                      Text(
                        frequency.cadenceNote,
                        style: context.typography.ui(
                          size: 10.5,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (frequency != HabitFrequency.values.last)
            const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _ColorSelector extends StatelessWidget {
  const _ColorSelector({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final hex in habitColorHexes)
          Semantics(
            button: true,
            selected: hex == selected,
            label: 'Colour $hex',
            child: GestureDetector(
              onTap: () => onChanged(hex),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: context.motion.fast,
                curve: AppMotion.spring,
                width: minTouchTarget,
                height: minTouchTarget,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: habitColorFromHex(hex, palette.accent)
                      .withValues(alpha: hex == selected ? 1 : 0.55),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hex == selected
                        ? palette.textPrimary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: hex == selected
                    ? Icon(PhLight.check, size: 16, color: palette.onAccent)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// Read-only context while editing: what the streak currently stands at and
/// where it came from, so deleting is an informed choice.
class _StreakNote extends StatelessWidget {
  const _StreakNote({required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final noun = habit.frequency.periodNoun;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Row(
        children: [
          Icon(PhLight.fire, size: 16, color: palette.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              habit.streakCount == 0
                  ? 'No streak running. '
                      '${habit.completedDates.length} completions recorded.'
                  : '${habit.streakCount} $noun'
                      '${habit.streakCount == 1 ? '' : 's'} in a row, from '
                      '${habit.completedDates.length} completions.',
              style: context.typography.ui(
                size: 12.5,
                color: palette.textMuted,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small circular icon button for a sheet's title row.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.tint,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String semanticLabel;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = tint ?? palette.textSecondary;

    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}
