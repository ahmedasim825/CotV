import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/task.dart';
import '../../models/task_view.dart';
import '../../providers/task_providers.dart';
import '../format/time_format.dart';
import '../theme/app_theme.dart';
import '../theme/prayer_palette.dart';
import '../widgets/glow_pill_button.dart';
import '../widgets/ph_light_icons.dart';

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
  return showModalBottomSheet<Task>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // The sheet is a form: dragging it away mid-edit loses work, so it
    // closes only via Cancel, Save, or the scrim.
    enableDrag: false,
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
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      // Lifts the sheet above the keyboard as it opens.
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          border: Border(top: BorderSide(color: AppPalette.innerHighlight)),
        ),
        child: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetGrabber(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                    children: [
                      Text(
                        _isEditing ? 'Edit task' : 'New task',
                        style: AppTypography.display(size: 26, weight: FontWeight.w500),
                      ),
                      const SizedBox(height: 22),
                      _FieldLabel(icon: PhLight.listChecks, label: 'Title'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        autofocus: !_isEditing,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.sentences,
                        style: AppTypography.ui(size: 15),
                        decoration: _inputDecoration('What needs doing?'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Give the task a title.'
                                : null,
                      ),
                      const SizedBox(height: 20),
                      _FieldLabel(
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
                        style: AppTypography.ui(size: 14),
                        decoration: _inputDecoration('Any detail worth keeping'),
                      ),
                      const SizedBox(height: 20),
                      _FieldLabel(icon: PhLight.tag, label: 'Category'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _categoryController,
                        textCapitalization: TextCapitalization.words,
                        style: AppTypography.ui(size: 14),
                        decoration: _inputDecoration('General'),
                      ),
                      const SizedBox(height: 22),
                      _FieldLabel(icon: PhLight.flagPennant, label: 'Priority'),
                      const SizedBox(height: 10),
                      _PrioritySelector(
                        selected: _priority,
                        onChanged: (value) => setState(() => _priority = value),
                      ),
                      const SizedBox(height: 22),
                      _FieldLabel(
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
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: GlowPillButton(
                              label: 'Cancel',
                              icon: PhLight.x,
                              filled: false,
                              expand: true,
                              onPressed: _isSaving
                                  ? null
                                  : () => Navigator.of(context).pop(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GlowPillButton(
                              label: _isEditing ? 'Save' : 'Add task',
                              icon: PhLight.check,
                              expand: true,
                              loading: _isSaving,
                              onPressed: _isSaving ? null : _save,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.ui(size: 14, color: AppPalette.textMuted),
      filled: true,
      fillColor: AppPalette.glassFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(AppPalette.glassBorder),
      enabledBorder: border(AppPalette.glassBorder),
      focusedBorder: border(AppPalette.amber),
      errorBorder: border(AppPalette.danger),
      focusedErrorBorder: border(AppPalette.danger),
      errorStyle: AppTypography.ui(size: 11.5, color: AppPalette.danger),
    );
  }
}

class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      decoration: BoxDecoration(
        color: AppPalette.glassBorder,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({
    required this.icon,
    required this.label,
    this.optional = false,
  });

  final IconData icon;
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppPalette.amber),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: AppTypography.eyebrow(color: AppPalette.textSecondary),
        ),
        if (optional) ...[
          const SizedBox(width: 8),
          Text(
            'OPTIONAL',
            style: AppTypography.eyebrow(color: AppPalette.textMuted),
          ),
        ],
      ],
    );
  }
}

class _PrioritySelector extends StatelessWidget {
  const _PrioritySelector({required this.selected, required this.onChanged});

  final TaskPriority selected;
  final ValueChanged<TaskPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    // High first: the order the list sorts in.
    const ordered = [TaskPriority.high, TaskPriority.medium, TaskPriority.low];

    return Row(
      children: [
        for (final priority in ordered) ...[
          Expanded(
            child: _PriorityChip(
              priority: priority,
              isSelected: priority == selected,
              onTap: () => onChanged(priority),
            ),
          ),
          if (priority != ordered.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({
    required this.priority,
    required this.isSelected,
    required this.onTap,
  });

  final TaskPriority priority;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = accentForPriority(priority);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${priority.label} priority',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.spring,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.16)
                : AppPalette.glassFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? accent : AppPalette.glassBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhLight.flagPennant,
                size: 13,
                color: isSelected ? accent : AppPalette.textMuted,
              ),
              const SizedBox(width: 7),
              Text(
                priority.label,
                style: AppTypography.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: isSelected ? accent : AppPalette.textSecondary,
                ),
              ),
            ],
          ),
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
                color: AppPalette.glassFill,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: due == null ? AppPalette.glassBorder : AppPalette.amber,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    PhLight.calendarBlank,
                    size: 15,
                    color: due == null ? AppPalette.textMuted : AppPalette.amber,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      due == null
                          ? 'No due date'
                          : '${formatFullDate(due)} · ${formatClock(due)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.ui(
                        size: 13.5,
                        color: due == null
                            ? AppPalette.textMuted
                            : AppPalette.textPrimary,
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
                  color: AppPalette.glassFill,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppPalette.glassBorder),
                ),
                child: const Icon(PhLight.x, size: 15, color: AppPalette.textMuted),
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
          color: AppPalette.glassFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.glassBorder),
        ),
        child: Row(
          children: [
            Icon(
              isOn ? PhLight.bellSimple : PhLight.bellSimpleSlash,
              size: 16,
              color: isOn ? AppPalette.amber : AppPalette.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reminder',
                    style: AppTypography.ui(size: 13.5, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'Notify me when this task is due'
                        : 'Set a due date to enable reminders',
                    style: AppTypography.ui(size: 11.5, color: AppPalette.textMuted),
                  ),
                ],
              ),
            ),
            Switch(
              value: isOn,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: AppPalette.onAmber,
              activeTrackColor: AppPalette.amber,
              inactiveThumbColor: AppPalette.textMuted,
              inactiveTrackColor: AppPalette.glassFill,
            ),
          ],
        ),
      ),
    );
  }
}
