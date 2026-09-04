import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../models/study_view.dart';
import '../../../models/subject.dart';
import '../../../providers/study_providers.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import '../subject_colors.dart';

const _uuid = Uuid();

/// Opens the create/edit subject sheet. Pass [existing] to edit, omit it to
/// create.
///
/// Resolves to the saved [Subject], or null if the sheet was dismissed or
/// the subject was deleted.
Future<Subject?> showSubjectFormSheet(
  BuildContext context, {
  Subject? existing,
}) {
  return showStandardBottomSheet<Subject>(
    context,
    builder: (_) => SubjectFormSheet(existing: existing),
  );
}

/// Bottom-sheet form for creating and editing a [Subject].
class SubjectFormSheet extends ConsumerStatefulWidget {
  const SubjectFormSheet({super.key, this.existing});

  final Subject? existing;

  @override
  ConsumerState<SubjectFormSheet> createState() => _SubjectFormSheetState();
}

class _SubjectFormSheetState extends ConsumerState<SubjectFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;

  late int _colorValue;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _colorValue = existing?.colorValue ?? subjectColorValues.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Whether another subject already carries this name.
  ///
  /// Enforced because Milo resolves "start a timer for physiology" by name:
  /// two subjects called Physiology make that lookup a coin toss, and the
  /// user would have no way to tell which one the minutes landed on.
  bool _isNameTaken(String name) {
    final existing = ref.read(subjectRepositoryProvider).findByName(name);
    return existing != null && existing.id != widget.existing?.id;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSaving = true);

    final name = _nameController.text.trim();
    final existing = widget.existing;
    final notifier = ref.read(subjectListProvider.notifier);

    final Subject saved;
    if (existing == null) {
      saved = Subject(id: _uuid.v4(), name: name, colorValue: _colorValue);
      await notifier.addSubject(saved);
    } else {
      saved = existing.copyWith(name: name, colorValue: _colorValue);
      await notifier.updateSubject(saved);
    }

    if (mounted) Navigator.of(context).pop(saved);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final logged = ref.read(studySummaryProvider).totalFor(existing.id);
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete subject?',
      // The logs survive — they are denormalised — so this says what
      // actually happens rather than implying the history is lost.
      message: 'Removing "${existing.name}" takes it off the grid. '
          '${logged == null ? 'Nothing has been logged against it this week.' : 'The '
              '${formatStudyMinutes(logged.weekMinutes)} already logged against '
              'it this week stays in the record.'}',
      confirmIcon: PhLight.trash,
    );
    if (!confirmed || !mounted) return;

    await ref.read(subjectListProvider.notifier).deleteSubject(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Form(
      key: _formKey,
      child: StandardBottomSheet(
        title: _isEditing ? 'Edit subject' : 'New subject',
        heightFactor: 0.8,
        trailing: _isEditing
            ? _IconAction(
                icon: PhLight.trash,
                tint: palette.danger,
                semanticLabel: 'Delete subject',
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
                label: _isEditing ? 'Save' : 'Add subject',
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
            const FieldLabel(icon: PhLight.bookOpen, label: 'Subject'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              autofocus: !_isEditing,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.sentences,
              style: context.typography.ui(size: 15),
              decoration: appInputDecoration(
                context,
                hint: 'Physiology, Anatomy, Pharmacology…',
              ),
              validator: (value) {
                final name = value?.trim() ?? '';
                if (name.isEmpty) return 'Give the subject a name.';
                if (_isNameTaken(name)) {
                  return 'There is already a subject called "$name".';
                }
                return null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 22),
            const FieldLabel(icon: PhLight.swatches, label: 'Colour'),
            const SizedBox(height: 12),
            _ColorSelector(
              selected: _colorValue,
              onChanged: (value) => setState(() => _colorValue = value),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 22),
              _LoggedNote(subject: widget.existing!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColorSelector extends StatelessWidget {
  const _ColorSelector({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final value in subjectColorValues)
          Semantics(
            button: true,
            selected: value == selected,
            label: 'Colour ${value.toRadixString(16)}',
            child: GestureDetector(
              onTap: () => onChanged(value),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: context.motion.fast,
                curve: AppMotion.spring,
                width: minTouchTarget,
                height: minTouchTarget,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: subjectColor(value)
                      .withValues(alpha: value == selected ? 1 : 0.55),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: value == selected
                        ? palette.textPrimary
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: value == selected
                    ? Icon(PhLight.check, size: 16, color: palette.onAccent)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

/// Read-only context while editing: what has actually been studied, so
/// deleting is an informed choice.
class _LoggedNote extends ConsumerWidget {
  const _LoggedNote({required this.subject});

  final Subject subject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final total = ref.watch(studySummaryProvider).totalFor(subject.id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.glassFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Row(
        children: [
          Icon(PhLight.clockCountdown, size: 16, color: palette.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              total == null
                  ? 'Nothing logged this week.'
                  : '${formatStudyMinutes(total.weekMinutes)} this week, '
                      '${formatStudyMinutes(total.todayMinutes)} of it today.',
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
