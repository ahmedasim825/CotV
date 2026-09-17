import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/task.dart';
import '../../providers/task_providers.dart';
import '../components/components.dart';
import '../format/time_format.dart';
import '../theme/app_theme.dart';
import '../widgets/ph_light_icons.dart';
import 'widgets/priority_selector.dart';
import 'widgets/sheet_icon_action.dart';

const _uuid = Uuid();

/// Opens the create/edit task sheet. Pass [existing] to edit, omit it to
/// create.
///
/// Resolves to the saved [Task], or null if the user dismissed the sheet.
Future<Task?> showTaskFormSheet(
  BuildContext context, {
  Task? existing,
  DateTime? initialDueDate,
}) {
  return showStandardBottomSheet<Task>(
    context,
    builder: (_) => TaskFormSheet(
      existing: existing,
      initialDueDate: initialDueDate,
    ),
  );
}

/// Bottom-sheet form for creating and editing a [Task].
class TaskFormSheet extends ConsumerStatefulWidget {
  const TaskFormSheet({super.key, this.existing, this.initialDueDate});

  final Task? existing;
  final DateTime? initialDueDate;

  @override
  ConsumerState<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<TaskFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _categoryController;

  late TaskPriority _priority;
  late DateTime? _dueDate;
  late bool _reminderEnabled;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _categoryController =
        TextEditingController(text: existing?.category ?? 'General');
    _priority = existing?.priority ?? TaskPriority.medium;
    _dueDate = existing?.dueDate ?? widget.initialDueDate;
    // A reminder needs a due date to anchor it to. New tasks that arrive
    // with one default to reminding; edits keep whatever was saved.
    _reminderEnabled =
        existing?.hasReminder ?? (_dueDate != null);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final base = _dueDate ?? now;

    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (!mounted) return;

    setState(() {
      _dueDate = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 0,
        time?.minute ?? 0,
      );
      _reminderEnabled = true;
    });
  }

  void _clearDueDate() {
    setState(() {
      _dueDate = null;
      // Nothing left to remind against.
      _reminderEnabled = false;
    });
  }

  /// Deletes the task being edited, behind a confirmation.
  ///
  /// This is the only way to delete a task. The list it is reached from draws
  /// its rows inside a ruled card with rounded outer corners only, where a
  /// swipe-to-delete panel sliding out behind a middle row has nowhere to
  /// sit — so the gesture moved here, where the reminder sheet already kept
  /// its own.
  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final confirmed = await confirmDestructive(
      context,
      title: 'Delete task?',
      message: 'Removing "${existing.title}" cannot be undone.',
      confirmIcon: PhLight.trash,
    );
    if (!confirmed || !mounted) return;

    await ref.read(taskListProvider.notifier).deleteTask(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final category = _categoryController.text.trim().isEmpty
        ? 'General'
        : _categoryController.text.trim();

    final existing = widget.existing;
    final notifier = ref.read(taskListProvider.notifier);

    final Task saved;
    if (existing == null) {
      saved = Task(
        id: _uuid.v4(),
        title: title,
        description: description,
        category: category,
        priority: _priority,
        dueDate: _dueDate,
        hasReminder: _reminderEnabled,
      );
      await notifier.addTask(saved);
    } else {
      saved = existing.copyWith(
        title: title,
        description: description,
        category: category,
        priority: _priority,
        dueDate: _dueDate,
        clearDueDate: _dueDate == null,
        hasReminder: _reminderEnabled,
      );
      await notifier.updateTask(saved);
    }

    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: StandardBottomSheet(
        title: _isEditing ? 'Edit task' : 'New task',
        trailing: _isEditing
            ? SheetIconAction(
                icon: PhLight.trash,
                tint: context.palette.danger,
                semanticLabel: 'Delete task',
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
                label: _isEditing ? 'Save' : 'Add task',
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
                      FieldLabel(icon: PhLight.listChecks, label: 'Title'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        autofocus: !_isEditing,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.sentences,
                        style: context.typography.ui(size: 15),
                        decoration: appInputDecoration(context, hint: 'What needs doing?'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Give the task a title.'
                                : null,
                      ),
                      const SizedBox(height: 20),
                      FieldLabel(
                        icon: PhLight.textAlignLeft,
                        label: 'Description',
                        optional: true,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        minLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        style: context.typography.ui(size: 14),
                        decoration: appInputDecoration(context, hint: 'Any detail worth keeping'),
                      ),
                      const SizedBox(height: 20),
                      FieldLabel(icon: PhLight.tag, label: 'Category'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _categoryController,
                        textCapitalization: TextCapitalization.words,
                        style: context.typography.ui(size: 14),
                        decoration: appInputDecoration(context, hint: 'General'),
                      ),
                      const SizedBox(height: 22),
                      FieldLabel(icon: PhLight.flagPennant, label: 'Priority'),
                      const SizedBox(height: 10),
                      PrioritySelector(
                        selected: _priority,
                        onChanged: (value) => setState(() => _priority = value),
                      ),
                      const SizedBox(height: 22),
                      FieldLabel(
                        icon: PhLight.clock,
                        label: 'Due date & time',
                        optional: true,
                      ),
                      const SizedBox(height: 10),
                      _DueDateField(
                        dueDate: _dueDate,
                        onPick: _pickDueDate,
                        onClear: _clearDueDate,
                      ),
                      const SizedBox(height: 18),
                      _ReminderToggle(
                        value: _reminderEnabled,
                        // A reminder needs a due date to fire against.
                        enabled: _dueDate != null,
                        onChanged: (value) =>
                            setState(() => _reminderEnabled = value),
                      ),
          ],
        ),
      ),
    );
  }

}

class _DueDateField extends StatelessWidget {
  const _DueDateField({
    required this.dueDate,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? dueDate;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final due = dueDate;

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onPick,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: context.palette.glassFill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: due == null ? context.palette.glassBorder : context.palette.accent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    PhLight.calendarBlank,
                    size: 15,
                    color: due == null ? context.palette.textMuted : context.palette.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      due == null
                          ? 'No due date'
                          : '${formatFullDate(due)} · ${formatClock(due)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typography.ui(
                        size: 13.5,
                        color: due == null
                            ? context.palette.textMuted
                            : context.palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (due != null) ...[
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: 'Clear due date',
            child: GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.palette.glassFill,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.palette.glassBorder),
                ),
                child: Icon(PhLight.x, size: 15, color: context.palette.textMuted),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReminderToggle extends StatelessWidget {
  const _ReminderToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final isOn = enabled && value;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        decoration: BoxDecoration(
          color: context.palette.glassFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.palette.glassBorder),
        ),
        child: Row(
          children: [
            Icon(
              isOn ? PhLight.bellSimple : PhLight.bellSimpleSlash,
              size: 16,
              color: isOn ? context.palette.accent : context.palette.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reminder',
                    style: context.typography.ui(size: 13.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'Notify me when this task is due'
                        : 'Set a due date to enable reminders',
                    style: context.typography.ui(size: 11.5, color: context.palette.textMuted),
                  ),
                ],
              ),
            ),
            Switch(
              value: isOn,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: context.palette.onAccent,
              activeTrackColor: context.palette.accent,
              inactiveThumbColor: context.palette.textMuted,
              inactiveTrackColor: context.palette.glassFill,
            ),
          ],
        ),
      ),
    );
  }
}
