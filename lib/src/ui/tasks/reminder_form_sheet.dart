import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/reminder.dart';
import '../../providers/reminder_providers.dart';
import '../components/components.dart';
import '../format/time_format.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';

const _uuid = Uuid();

/// Add a reminder, or edit [existing].
///
/// Ids come from `uuid`, which the app already depends on and which
/// `task_form_sheet.dart` uses for the same purpose.
Future<void> showReminderFormSheet(
  BuildContext context, {
  Reminder? existing,
}) {
  return showStandardBottomSheet<void>(
    context,
    builder: (_) => ReminderFormSheet(existing: existing),
  );
}

/// Bottom-sheet form for creating and editing a [Reminder].
class ReminderFormSheet extends ConsumerStatefulWidget {
  const ReminderFormSheet({super.key, this.existing});

  final Reminder? existing;

  @override
  ConsumerState<ReminderFormSheet> createState() => _ReminderFormSheetState();
}

class _ReminderFormSheetState extends ConsumerState<ReminderFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late DateTime _dueAt;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _dueAt = existing?.dueAt ?? _nextHour(DateTime.now());
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  /// Rounds [now] down to the hour, then advances one — so a fresh reminder
  /// always defaults to a moment still ahead of it, never the hour that just
  /// started.
  static DateTime _nextHour(DateTime now) =>
      DateTime(now.year, now.month, now.day, now.hour)
          .add(const Duration(hours: 1));

  Future<void> _pickDueAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: DateTime(_dueAt.year - 1),
      lastDate: DateTime(_dueAt.year + 5),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt),
    );
    if (!mounted) return;

    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _dueAt.hour,
        time?.minute ?? _dueAt.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final title = _titleController.text.trim();
    final existing = widget.existing;
    final notifier = ref.read(reminderListProvider.notifier);

    if (existing == null) {
      notifier.add(Reminder(id: _uuid.v4(), title: title, dueAt: _dueAt));
    } else {
      notifier.update(existing.copyWith(title: title, dueAt: _dueAt));
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final confirmed = await confirmDestructive(
      context,
      title: 'Delete reminder?',
      message: 'Removing "${existing.title}" cannot be undone.',
      confirmIcon: PhLight.trash,
    );
    if (!confirmed || !mounted) return;

    ref.read(reminderListProvider.notifier).remove(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Form(
      key: _formKey,
      child: StandardBottomSheet(
        title: _isEditing ? 'Edit reminder' : 'New reminder',
        trailing: _isEditing
            ? _IconAction(
                icon: PhLight.trash,
                tint: palette.danger,
                semanticLabel: 'Delete reminder',
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
                label: _isEditing ? 'Save' : 'Add reminder',
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
            FieldLabel(icon: PhLight.bellSimple, label: 'Title'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleController,
              autofocus: !_isEditing,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              style: context.typography.ui(size: 15),
              decoration:
                  appInputDecoration(context, hint: 'What should I remind you of?'),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Give the reminder a title.'
                  : null,
            ),
            const SizedBox(height: 22),
            FieldLabel(icon: PhLight.clock, label: 'Due date & time'),
            const SizedBox(height: 10),
            _DueAtField(dueAt: _dueAt, onPick: _pickDueAt),
          ],
        ),
      ),
    );
  }
}

/// A small circular icon button for a sheet's title row.
///
/// Mirrors `habit_form_sheet.dart`'s private widget of the same name and
/// shape — both sheets put a destructive action in the same spot, and
/// neither is worth promoting to a shared component for one field each.
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

class _DueAtField extends StatelessWidget {
  const _DueAtField({required this.dueAt, required this.onPick});

  final DateTime dueAt;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.palette.glassFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.palette.accent),
        ),
        child: Row(
          children: [
            Icon(PhLight.calendarBlank, size: 15, color: context.palette.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${formatFullDate(dueAt)} · ${formatClock(dueAt)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.typography.ui(
                  size: 13.5,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
