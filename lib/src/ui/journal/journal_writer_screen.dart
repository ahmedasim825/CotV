import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/journal_entry.dart';
import '../../models/journal_view.dart';
import '../../providers/journal_providers.dart';
import '../components/components.dart';
import '../format/time_format.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/ph_light_icons.dart';
import '../widgets/status_card.dart';
import 'markdown/markdown_view.dart';
import 'widgets/mood_picker.dart';
import 'widgets/tag_chip.dart';

const _uuid = Uuid();

/// Pushes the full-screen journal writer. Pass [existing] to edit an entry,
/// or [initialDate] to start a new one on a specific day.
Future<void> openJournalWriter(
  BuildContext context, {
  JournalEntry? existing,
  DateTime? initialDate,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => JournalWriterScreen(
        existing: existing,
        initialDate: initialDate,
      ),
    ),
  );
}

/// The writing surface: a markdown editor with a formatting toolbar pinned
/// above the keyboard, a live preview toggle, a mood picker and tags.
class JournalWriterScreen extends ConsumerStatefulWidget {
  const JournalWriterScreen({super.key, this.existing, this.initialDate});

  final JournalEntry? existing;
  final DateTime? initialDate;

  @override
  ConsumerState<JournalWriterScreen> createState() =>
      _JournalWriterScreenState();
}

class _JournalWriterScreenState extends ConsumerState<JournalWriterScreen> {
  late final TextEditingController _contentController;
  late final TextEditingController _tagController;
  final _contentFocus = FocusNode();

  late DateTime _date;
  late JournalMood _mood;
  late List<String> _tags;

  late final String _initialContent;
  late final JournalMood _initialMood;
  late final List<String> _initialTags;
  late final DateTime _initialDate;

  bool _isPreviewing = false;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _date = normalizeJournalDate(
      existing?.date ?? widget.initialDate ?? DateTime.now(),
    );
    _mood = existing?.mood ?? JournalMood.neutral;
    _tags = [...?existing?.tags];

    _contentController = TextEditingController(text: existing?.content ?? '');
    _tagController = TextEditingController();

    // Snapshotted so "has anything changed?" is a comparison rather than a
    // flag that every handler has to remember to set.
    _initialContent = _contentController.text;
    _initialMood = _mood;
    _initialTags = [..._tags];
    _initialDate = _date;

    _contentController.addListener(_onContentChanged);
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _contentController.dispose();
    _tagController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _onContentChanged() {
    // Only the dirty indicator and the empty-state hint depend on the text,
    // so rebuild at most once per transition rather than per keystroke.
    final nowDirty = _isDirty;
    if (nowDirty != _wasDirty) {
      _wasDirty = nowDirty;
      setState(() {});
    }
  }

  bool _wasDirty = false;

  bool get _isDirty {
    if (_contentController.text != _initialContent) return true;
    if (_mood != _initialMood) return true;
    if (_date != _initialDate) return true;
    if (_tags.length != _initialTags.length) return true;
    for (var i = 0; i < _tags.length; i++) {
      if (_tags[i] != _initialTags[i]) return true;
    }
    return false;
  }

  // -- editing helpers ------------------------------------------------------

  TextSelection get _safeSelection {
    final selection = _contentController.selection;
    if (selection.start < 0 || selection.end < 0) {
      return TextSelection.collapsed(offset: _contentController.text.length);
    }
    return selection;
  }

  /// Wraps the selection in [prefix]/[suffix], or drops in the pair with the
  /// caret between them when nothing is selected.
  void _wrapSelection(String prefix, String suffix) {
    final text = _contentController.text;
    final selection = _safeSelection;
    final selected = text.substring(selection.start, selection.end);

    final replacement = '$prefix$selected$suffix';
    _contentController.value = TextEditingValue(
      text: text.replaceRange(selection.start, selection.end, replacement),
      selection: TextSelection(
        baseOffset: selection.start + prefix.length,
        extentOffset: selection.start + prefix.length + selected.length,
      ),
    );
    _contentFocus.requestFocus();
    setState(() {});
  }

  /// Puts [marker] at the start of the line the caret sits on, adding a
  /// blank line above it when it would otherwise join the previous
  /// paragraph.
  void _prefixLine(String marker) {
    final text = _contentController.text;
    final selection = _safeSelection;

    var lineStart = selection.start;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }

    final needsBreak = lineStart > 0 &&
        lineStart == selection.start &&
        text[lineStart - 1] == '\n' &&
        lineStart >= 2 &&
        text[lineStart - 2] != '\n';
    final insertion = needsBreak ? '\n$marker' : marker;

    _contentController.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineStart, insertion),
      selection: TextSelection.collapsed(
        offset: selection.end + insertion.length,
      ),
    );
    _contentFocus.requestFocus();
    setState(() {});
  }

  void _addTag() {
    final tag = normalizeTag(_tagController.text);
    if (tag.isEmpty) return;
    if (_tags.contains(tag)) {
      _tagController.clear();
      return;
    }
    setState(() {
      _tags = [..._tags, tag];
      _tagController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() => _tags = _tags.where((t) => t != tag).toList());
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      // Journals record what happened; there is nothing to write about a
      // day that has not happened yet.
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = normalizeJournalDate(picked);
      _errorMessage = null;
    });
  }

  // -- persistence ----------------------------------------------------------

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() => _errorMessage = 'Write something before saving.');
      return;
    }

    final notifier = ref.read(journalListProvider.notifier);

    // One entry per day: without this, backdating a new entry onto a day
    // that already has one would quietly create a second, and the list
    // would show two cards for the same date.
    final clash = notifier.getByDate(_date);
    if (clash != null && clash.id != widget.existing?.id) {
      setState(() {
        _errorMessage =
            'An entry already exists for ${formatFullDate(_date)}. '
            'Open that one, or pick another date.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final existing = widget.existing;
    if (existing == null) {
      await notifier.addEntry(
        JournalEntry(
          id: _uuid.v4(),
          date: _date,
          content: content,
          mood: _mood,
          tags: _tags,
        ),
      );
    } else {
      await notifier.updateEntry(
        existing.copyWith(
          date: _date,
          content: content,
          mood: _mood,
          tags: _tags,
        ),
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final confirmed = await confirmDestructive(
      context,
      title: 'Delete entry?',
      message: 'The entry for ${formatFullDate(existing.date)} will be '
          'removed. This cannot be undone.',
      confirmIcon: PhLight.trash,
    );
    if (!confirmed || !mounted) return;

    await ref.read(journalListProvider.notifier).deleteEntry(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDiscard() async {
    final discard = await confirmDestructive(
      context,
      title: 'Discard changes?',
      message: 'This entry has unsaved edits. Leaving now loses them.',
      confirmLabel: 'Discard',
      cancelLabel: 'Keep editing',
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  // -- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AmbientBackground(
          child: SafeArea(
            child: Column(
              children: [
                _WriterBar(
                  date: _date,
                  isEditing: _isEditing,
                  isPreviewing: _isPreviewing,
                  isSaving: _isSaving,
                  isDirty: _isDirty,
                  onBack: () {
                    if (_isDirty) {
                      _confirmDiscard();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  onPickDate: _pickDate,
                  onTogglePreview: () =>
                      setState(() => _isPreviewing = !_isPreviewing),
                  onDelete: _isEditing ? _delete : null,
                  onSave: _isSaving ? null : _save,
                ),
                Expanded(
                  child: _isPreviewing
                      ? _Preview(
                          content: _contentController.text,
                          mood: _mood,
                          tags: _tags,
                        )
                      : _Editor(
                          contentController: _contentController,
                          contentFocus: _contentFocus,
                          tagController: _tagController,
                          mood: _mood,
                          tags: _tags,
                          errorMessage: _errorMessage,
                          onMoodChanged: (mood) => setState(() => _mood = mood),
                          onAddTag: _addTag,
                          onRemoveTag: _removeTag,
                        ),
                ),
                if (!_isPreviewing)
                  _MarkdownToolbar(
                    onWrap: _wrapSelection,
                    onPrefix: _prefixLine,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Midnight-normalized: an entry belongs to a day, not an instant.
DateTime normalizeJournalDate(DateTime date) =>
    DateTime(date.year, date.month, date.day);

class _WriterBar extends StatelessWidget {
  const _WriterBar({
    required this.date,
    required this.isEditing,
    required this.isPreviewing,
    required this.isSaving,
    required this.isDirty,
    required this.onBack,
    required this.onPickDate,
    required this.onTogglePreview,
    required this.onDelete,
    required this.onSave,
  });

  final DateTime date;
  final bool isEditing;
  final bool isPreviewing;
  final bool isSaving;
  final bool isDirty;
  final VoidCallback onBack;
  final VoidCallback onPickDate;
  final VoidCallback onTogglePreview;
  final VoidCallback? onDelete;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          _BarButton(
            icon: PhLight.arrowLeft,
            semanticLabel: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              button: true,
              label: 'Entry date, ${formatFullDate(date)}. Tap to change.',
              child: GestureDetector(
                onTap: onPickDate,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        formatShortDate(date),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.typography.ui(
                          size: 14,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      PhLight.caretDown,
                      size: 13,
                      color: palette.textMuted,
                    ),
                    if (isDirty) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          _BarButton(
            icon: isPreviewing ? PhLight.pencilSimple : PhLight.eye,
            semanticLabel: isPreviewing ? 'Back to editing' : 'Preview',
            selected: isPreviewing,
            onTap: onTogglePreview,
          ),
          if (onDelete != null) ...[
            const SizedBox(width: 8),
            _BarButton(
              icon: PhLight.trash,
              semanticLabel: 'Delete entry',
              tint: palette.danger,
              onTap: onDelete!,
            ),
          ],
          const SizedBox(width: 10),
          PrimaryButton(
            label: 'Save',
            icon: PhLight.floppyDisk,
            size: ButtonSize.compact,
            loading: isSaving,
            onPressed: onSave,
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.selected = false,
    this.tint,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool selected;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final color = tint ?? (selected ? palette.accent : palette.textSecondary);

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? palette.accentSoft : palette.glassFill,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? palette.accent : palette.glassBorder,
            ),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
      ),
    );
  }
}

class _Editor extends StatelessWidget {
  const _Editor({
    required this.contentController,
    required this.contentFocus,
    required this.tagController,
    required this.mood,
    required this.tags,
    required this.errorMessage,
    required this.onMoodChanged,
    required this.onAddTag,
    required this.onRemoveTag,
  });

  final TextEditingController contentController;
  final FocusNode contentFocus;
  final TextEditingController tagController;
  final JournalMood mood;
  final List<String> tags;
  final String? errorMessage;
  final ValueChanged<JournalMood> onMoodChanged;
  final VoidCallback onAddTag;
  final ValueChanged<String> onRemoveTag;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        const FieldLabel(icon: PhLight.smiley, label: 'Mood'),
        const SizedBox(height: 10),
        MoodPicker(selected: mood, onChanged: onMoodChanged),
        const SizedBox(height: 22),
        const FieldLabel(icon: PhLight.tag, label: 'Tags', optional: true),
        const SizedBox(height: 10),
        TextField(
          controller: tagController,
          textInputAction: TextInputAction.done,
          style: context.typography.ui(size: 14),
          decoration: appInputDecoration(
            context,
            hint: 'Add a tag and press return',
            suffixIcon: IconButton(
              icon: Icon(PhLight.plusCircle, size: 18, color: palette.accent),
              onPressed: onAddTag,
              tooltip: 'Add tag',
            ),
          ),
          onSubmitted: (_) => onAddTag(),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                TagChip(label: tag, onRemove: () => onRemoveTag(tag)),
            ],
          ),
        ],
        const SizedBox(height: 22),
        const FieldLabel(icon: PhLight.notePencil, label: 'Entry'),
        const SizedBox(height: 10),
        TextField(
          controller: contentController,
          focusNode: contentFocus,
          maxLines: null,
          minLines: 12,
          textCapitalization: TextCapitalization.sentences,
          keyboardType: TextInputType.multiline,
          style: context.typography.ui(
            size: 15,
            weight: FontWeight.w400,
            height: 1.6,
            color: palette.textPrimary,
          ),
          decoration: appInputDecoration(
            context,
            hint: 'How did today go?\n\nMarkdown works here — '
                '**bold**, *italic*, # headings, - lists.',
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
        if (errorMessage != null) ...[
          const SizedBox(height: 16),
          StatusCard(message: errorMessage!, tone: StatusTone.error),
        ],
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.content,
    required this.mood,
    required this.tags,
  });

  final String content;
  final JournalMood mood;
  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final trimmed = content.trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MoodGlyph(mood: mood),
              const SizedBox(width: 10),
              Text(
                mood.label,
                style: context.typography.ui(
                  size: 13,
                  weight: FontWeight.w600,
                  color: colorForMood(mood, palette),
                ),
              ),
            ],
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final tag in tags) TagChip(label: tag)],
            ),
          ],
          const SizedBox(height: 22),
          if (trimmed.isEmpty)
            Text(
              'Nothing to preview yet.',
              style: context.typography.ui(size: 14, color: palette.textMuted),
            )
          else
            MarkdownView(data: trimmed),
        ],
      ),
    );
  }
}

/// The formatting row, pinned directly above the keyboard.
class _MarkdownToolbar extends StatelessWidget {
  const _MarkdownToolbar({required this.onWrap, required this.onPrefix});

  final void Function(String prefix, String suffix) onWrap;
  final void Function(String marker) onPrefix;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        children: [
          _ToolButton(
            icon: PhLight.textB,
            label: 'Bold',
            onTap: () => onWrap('**', '**'),
          ),
          _ToolButton(
            icon: PhLight.textItalic,
            label: 'Italic',
            onTap: () => onWrap('*', '*'),
          ),
          _ToolButton(
            icon: PhLight.textHOne,
            label: 'Heading',
            onTap: () => onPrefix('## '),
          ),
          _ToolButton(
            icon: PhLight.listBullets,
            label: 'Bullet list',
            onTap: () => onPrefix('- '),
          ),
          _ToolButton(
            icon: PhLight.listNumbers,
            label: 'Numbered list',
            onTap: () => onPrefix('1. '),
          ),
          _ToolButton(
            icon: PhLight.quotes,
            label: 'Quote',
            onTap: () => onPrefix('> '),
          ),
          _ToolButton(
            icon: PhLight.code,
            label: 'Code',
            onTap: () => onWrap('`', '`'),
          ),
          _ToolButton(
            icon: PhLight.link,
            label: 'Link',
            onTap: () => onWrap('[', '](https://)'),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44,
          margin: const EdgeInsets.only(right: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.glassFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 17, color: palette.textSecondary),
        ),
      ),
    );
  }
}
