import 'dart:ui' show ImageFilter;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../models/subject.dart';
import '../../models/task.dart';
import '../../models/task_view.dart';
import '../../providers/study_providers.dart';
import '../../providers/task_providers.dart';
import '../components/components.dart';
import '../format/time_format.dart';
import '../platform/sf_symbols.dart';
import '../study/subject_colors.dart';
import '../theme/app_theme.dart';
import '../theme/prayer_palette.dart';
import '../widgets/ph_light_icons.dart';
import 'widgets/month_calendar.dart';
import 'widgets/native_switch.dart';
import 'widgets/picker_wheel.dart';
import 'widgets/pill_dropdown.dart';

const _uuid = Uuid();

/// Opens the task sheet. Pass [existing] to edit, omit it to create.
///
/// [initialTitle] is what the inline add row had typed in it when the ⓘ was
/// tapped — the sheet is that capture continued, not a second one started.
///
/// Resolves to the saved [Task], or null if the sheet was dismissed.
Future<Task?> showNewTaskSheet(
  BuildContext context, {
  Task? existing,
  DateTime? initialDueDate,
  String? initialTitle,
}) {
  return showStandardBottomSheet<Task>(
    context,
    builder: (_) => NewTaskSheet(
      existing: existing,
      initialDueDate: initialDueDate,
      initialTitle: initialTitle,
    ),
  );
}

/// The near-full-screen sheet behind the ⓘ, and behind a tap on any task row.
///
/// ## Not a [StandardBottomSheet]
///
/// That chrome is a grabber, a title and a pinned action row, and this design
/// has none of the three: the actions are two circles in a header *above* the
/// title, and the sheet is tall enough that pinning anything is pointless. It
/// borrows [showStandardBottomSheet] — the presenter, which already sets the
/// transparent background, the scrim barrier and the `enableDrag: false` every
/// form sheet wants — and draws its own body.
///
/// ## Not [LiquidGlass]
///
/// That widget states no ancestor may push a save layer or the shader samples
/// that buffer rather than the page. A modal route's transition pushes one, so
/// the refraction would silently do nothing here. A plain [BackdropFilter]
/// under [AppPalette.sheetGlass] is the read the design asks for, and the one
/// that actually renders.
///
/// ## What this sheet does not edit
///
/// A task's category. It survives an edit untouched — it is not named in
/// the `copyWith` below, which is what preserves it — and a new task takes
/// the model's default. It is absent because its design has not landed yet,
/// not because it was dropped. Priority used to sit here with it and no
/// longer does: its design arrived, so it is set and stored like any other
/// field.
///
/// Url, Study and the subject under it are the other way round: they are on
/// screen and they are **not stored**, because [Task] has a field for none of
/// them. Toggling Study, picking a subject, saving and reopening shows it off
/// and empty again. That is a lie the sheet tells on purpose, for one design
/// pass, and it ends when the fields land.
class NewTaskSheet extends ConsumerStatefulWidget {
  const NewTaskSheet({
    super.key,
    this.existing,
    this.initialDueDate,
    this.initialTitle,
  });

  final Task? existing;
  final DateTime? initialDueDate;
  final String? initialTitle;

  @override
  ConsumerState<NewTaskSheet> createState() => _NewTaskSheetState();
}

class _NewTaskSheetState extends ConsumerState<NewTaskSheet> {
  /// Share of the screen the sheet covers. Not all of it: the strip of ground
  /// left at the top is what says this is a sheet over the list rather than a
  /// page that replaced it.
  static const double _heightFactor = 0.93;

  static const double _gutter = 24;
  static const double _radius = 32;

  late final TextEditingController _title;
  late final TextEditingController _notes;

  /// Not persisted — see the class doc.
  final TextEditingController _url = TextEditingController();
  bool _isStudy = false;
  Subject? _subject;

  /// Back in the sheet now that its design has landed, and stored --
  /// unlike Study, Subject and Url, [Task] has carried a priority all
  /// along.
  late TaskPriority _priority;

  final _studySwitch = CNSwitchController();
  final _dateSwitch = CNSwitchController();
  final _timeSwitch = CNSwitchController();

  late bool _dateEnabled;
  late bool _timeEnabled;
  late DateTime _date;
  late DateTime _time;

  /// Which of the two Date & Time rows has its picker showing. Independent of
  /// each other: the design expands each under its own row, and both can be
  /// open at once.
  bool _calendarOpen = false;
  bool _wheelOpen = false;

  /// The month the calendar is showing, which drifts from [_date] as the
  /// steppers are used and only rejoins it when a day is picked.
  late DateTime _visibleMonth;

  bool _pickingMonth = false;
  bool _isSaving = false;

  /// Minutes move in fives. A wheel of sixty, for a field nobody sets to the
  /// minute, is a long scroll for a precision no one asked for.
  static const int _minuteStep = 5;
  static const int _minuteCount = 60 ~/ _minuteStep;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final due = existing?.dueDate ?? widget.initialDueDate;
    final now = DateTime.now();

    _title = TextEditingController(
      text: existing?.title ?? widget.initialTitle ?? '',
    );
    _notes = TextEditingController(text: existing?.description ?? '');

    _priority = existing?.priority ?? TaskPriority.medium;
    _dateEnabled = due != null;
    // Midnight is how a date with no time of day is stored — the model carries
    // one nullable due date, not a date and a time — and `formatDueLabel` has
    // read it that way since before this sheet existed.
    _timeEnabled = due != null && (due.hour != 0 || due.minute != 0);
    _date = due ?? startOfDay(now);
    _time = _timeEnabled ? due! : _roundToStep(now);
    _visibleMonth = DateTime(_date.year, _date.month);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _url.dispose();
    super.dispose();
  }

  /// The current time snapped to the wheel's minute step, so turning Time on
  /// lands on a value the wheel can actually show.
  static DateTime _roundToStep(DateTime time) {
    final step = (time.minute / _minuteStep).round() * _minuteStep;
    return DateTime(
      time.year,
      time.month,
      time.day,
      time.hour,
    ).add(Duration(minutes: step));
  }

  void _setDate(bool on) {
    setState(() {
      _dateEnabled = on;
      // Turning the date on is asking which day, so the calendar comes with
      // it rather than waiting for a second tap.
      _calendarOpen = on;
      if (on) {
        _visibleMonth = DateTime(_date.year, _date.month);
      } else {
        // A time with no day has nothing to anchor to.
        _timeEnabled = false;
        _wheelOpen = false;
        _pickingMonth = false;
        _timeSwitch.setValue(false, animated: true);
      }
    });
  }

  void _setTime(bool on) {
    setState(() {
      _timeEnabled = on;
      // Turning the time on is asking what it should be, so the wheel comes
      // with it rather than waiting for a second tap.
      _wheelOpen = on;
      if (on && !_dateEnabled) {
        _dateEnabled = true;
        _visibleMonth = DateTime(_date.year, _date.month);
        _dateSwitch.setValue(true, animated: true);
      }
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);

    final due = _dateEnabled
        ? DateTime(
            _date.year,
            _date.month,
            _date.day,
            _timeEnabled ? _time.hour : 0,
            _timeEnabled ? _time.minute : 0,
          )
        : null;

    final existing = widget.existing;
    final notifier = ref.read(taskListProvider.notifier);
    final notes = _notes.text.trim();

    final Task saved;
    if (existing == null) {
      saved = Task(
        id: _uuid.v4(),
        title: title,
        description: notes,
        dueDate: due,
        priority: _priority,
        // A task with a moment on it is one worth being told about; a task
        // with only a day is not, and firing at midnight for it would be
        // worse than not firing at all.
        hasReminder: _timeEnabled,
      );
      await notifier.addTask(saved);
    } else {
      saved = existing.copyWith(
        title: title,
        description: notes,
        dueDate: due,
        clearDueDate: due == null,
        priority: _priority,
        hasReminder: _timeEnabled,
      );
      await notifier.updateTask(saved);
    }

    if (mounted) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final canSave = _title.text.trim().isNotEmpty;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * _heightFactor,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(_radius),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.sheetGlass,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(_radius),
              ),
              border: Border.all(color: palette.hairline),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(palette, canSave: canSave),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(_gutter, 24, _gutter, 0),
                    child: Text(
                      _isEditing ? 'Edit Task' : 'New Task',
                      style: context.typography.display(
                        size: 28,
                        weight: FontWeight.w600,
                        letterSpacing: -0.8,
                      ),
                    ),
                  ),
                  // A fixed gap, outside the scroll view, so scrolled
                  // content is sliced off with air under the title rather
                  // than butting straight into it. The scroll view's own
                  // padding travels with the content and is gone the moment
                  // it moves, which is what left them touching.
                  const SizedBox(height: 20),
                  Expanded(child: _body(palette)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppPalette palette, {required bool canSave}) {
    return Padding(
      // 20, not the 24 gutter: each circle is centred in a 44pt target that
      // overhangs it by 4 a side, so the glyphs still line up with the text
      // below while the taps stay comfortable.
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          _CircleButton(
            icon: PhLight.x,
            fill: palette.glassFill,
            glyph: palette.textPrimary,
            semanticLabel: 'Close',
            onTap: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          AnimatedOpacity(
            opacity: canSave ? 1 : 0.4,
            duration: context.motion.fast,
            child: _CircleButton(
              icon: PhLight.check,
              fill: palette.accent,
              glyph: palette.onAccent,
              semanticLabel: _isEditing ? 'Save task' : 'Add task',
              onTap: canSave ? _save : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(AppPalette palette) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        _gutter,
        6,
        _gutter,
        // The sheet keeps its full height while the keyboard is up — lifting
        // something already covering 93% of the screen only squashes it — so
        // the inset goes on the scroll extent instead.
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldBox(
            children: [
              _SheetField(
                controller: _title,
                hint: 'Title',
                // The one field the save control watches.
                onChanged: (_) => setState(() {}),
                textCapitalization: TextCapitalization.sentences,
                autofocus: !_isEditing,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _FieldBox(
            children: [
              _SheetField(
                controller: _notes,
                hint: 'Notes',
                minLines: 1,
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
              ),
              _SheetField(
                controller: _url,
                hint: 'Url',
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSize(
            duration: context.motion.fast,
            curve: AppMotion.spring,
            alignment: Alignment.topCenter,
            child: _FieldBox(
              children: [
                _ToggleRow(
                  label: 'Study',
                  value: _isStudy,
                  controller: _studySwitch,
                  onChanged: (value) => setState(() {
                    _isStudy = value;
                    // A subject with the study flag off would be invisible
                    // state the sheet could still hand to a save.
                    if (!value) _subject = null;
                  }),
                ),
                if (_isStudy) _subjectRow(),
                _priorityRow(),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Date & Time',
            style: context.typography.ui(
              size: 15,
              weight: FontWeight.w500,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: context.motion.fast,
            curve: AppMotion.spring,
            alignment: Alignment.topCenter,
            child: _FieldBox(
              children: [
                _ToggleRow(
                  icon: PhLight.calendarBlank,
                  symbol: 'calendar',
                  label: 'Date',
                  subtitle: _dateEnabled ? _dateLabel() : null,
                  value: _dateEnabled,
                  controller: _dateSwitch,
                  onChanged: _setDate,
                  onTapLabel: _dateEnabled
                      ? () => setState(() => _calendarOpen = !_calendarOpen)
                      : null,
                ),
                if (_dateEnabled && _calendarOpen)
                  Padding(
                    // Inset to the label rather than the box, so the grid
                    // reads as belonging to the row above it.
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: MonthCalendar(
                      month: _visibleMonth,
                      selected: _date,
                      pickingMonth: _pickingMonth,
                      onTogglePicking: () =>
                          setState(() => _pickingMonth = !_pickingMonth),
                      onMonthChanged: (month) =>
                          setState(() => _visibleMonth = month),
                      onSelected: (day) => setState(() {
                        _date = day;
                        _visibleMonth = DateTime(day.year, day.month);
                      }),
                    ),
                  ),
                _ToggleRow(
                  icon: PhLight.clock,
                  symbol: 'clock',
                  label: 'Time',
                  subtitle: _timeEnabled ? formatClock(_time) : null,
                  value: _timeEnabled,
                  controller: _timeSwitch,
                  onChanged: _setTime,
                  onTapLabel: _timeEnabled
                      ? () => setState(() => _wheelOpen = !_wheelOpen)
                      : null,
                ),
                if (_timeEnabled && _wheelOpen) _timeWheel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A label at the leading edge with a [PillDropdown] at the trailing one.
  Widget _pickerRow({required String label, required Widget control}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.typography.ui(size: 16, weight: FontWeight.w500),
            ),
          ),
          control,
        ],
      ),
    );
  }

  /// The Study box's subject row. Chosen and shown, then dropped on save --
  /// see the class doc.
  Widget _subjectRow() {
    final subjects = ref.watch(subjectListProvider).value ?? const <Subject>[];
    // A subject deleted while the sheet is open stops matching, and the
    // control falls back to None rather than naming a row that is gone.
    final current = subjects
        .where((subject) => subject.id == _subject?.id)
        .firstOrNull;

    return _pickerRow(
      label: 'Subject',
      control: PillDropdown<String?>(
        semanticLabel: 'Subject',
        selected: current?.id,
        options: [
          // Null first: the entry that clears the choice, and what the
          // control says on its own before any subject has been made.
          const PillOption(value: null, label: 'None'),
          for (final subject in subjects)
            PillOption(
              value: subject.id,
              label: subject.name,
              color: subjectColor(subject.colorValue),
            ),
        ],
        onSelected: (id) => setState(() {
          _subject = subjects.where((s) => s.id == id).firstOrNull;
        }),
      ),
    );
  }

  Widget _priorityRow() {
    return _pickerRow(
      label: 'Priority',
      control: PillDropdown<TaskPriority>(
        semanticLabel: 'Priority',
        selected: _priority,
        options: [
          // Low first, the order the design lists them -- the opposite of
          // `PrioritySelector`, whose row leads with High to match how the
          // list sorts.
          for (final priority in TaskPriority.values)
            PillOption(
              value: priority,
              label: priority.label,
              color: context.palette.priorityColor(priority),
            ),
        ],
        onSelected: (priority) => setState(() => _priority = priority),
      ),
    );
  }

  Widget _timeWheel() {
    return PickerWheel(
      columns: [
        WheelColumn(
          count: 24,
          selected: _time.hour,
          label: padTwo,
          onChanged: (hour) => setState(
            () => _time = DateTime(
              _date.year,
              _date.month,
              _date.day,
              hour,
              _time.minute,
            ),
          ),
        ),
        WheelColumn(
          count: _minuteCount,
          selected: _time.minute ~/ _minuteStep,
          label: (index) => padTwo(index * _minuteStep),
          onChanged: (index) => setState(
            () => _time = DateTime(
              _date.year,
              _date.month,
              _date.day,
              _time.hour,
              index * _minuteStep,
            ),
          ),
        ),
      ],
    );
  }

  String _dateLabel() =>
      relativeDayName(startOfDay(_date), startOfDay(DateTime.now())) ??
      formatShortDate(_date);
}

/// One of the two circles in the header.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.fill,
    required this.glyph,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color fill;
  final Color glyph;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: glyph),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rounded plate one or more fields share, ruled between them.
class _FieldBox extends StatelessWidget {
  const _FieldBox({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final ruled = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        ruled.add(Container(height: 1, color: palette.fieldDivider));
      }
      ruled.add(children[i]);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.fieldFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.fieldBorder),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: ruled),
      ),
    );
  }
}

/// A borderless text field sized to sit inside a [_FieldBox], which draws the
/// plate and the rim this would otherwise carry itself.
class _SheetField extends StatelessWidget {
  const _SheetField({
    required this.controller,
    required this.hint,
    this.onChanged,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.minLines,
    this.maxLines = 1,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int? minLines;
  final int? maxLines;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = context.typography.ui(size: 17, weight: FontWeight.w400);

    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      minLines: minLines,
      maxLines: maxLines,
      autofocus: autofocus,
      style: style,
      cursorColor: palette.accent,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintText: hint,
        hintStyle: style.copyWith(color: palette.textMuted),
      ),
    );
  }
}

/// A label, an optional accent subtitle and a switch, on one row of a
/// [_FieldBox].
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.controller,
    this.icon,
    this.symbol,
    this.subtitle,
    this.onTapLabel,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final CNSwitchController? controller;

  /// The Phosphor glyph, and the SF Symbol name it stands in for off Apple
  /// platforms. Both null on a row the design draws without an icon.
  final IconData? icon;
  final String? symbol;

  final String? subtitle;

  /// Tapping the label rather than the switch — the Time row uses it to show
  /// and hide the wheel without turning the time off.
  final VoidCallback? onTapLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final glyph = icon;
    final name = symbol;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: context.typography.ui(size: 16, weight: FontWeight.w500),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: context.typography.ui(
              size: 13,
              weight: FontWeight.w500,
              color: palette.accent,
            ),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
      child: Row(
        children: [
          if (glyph != null && name != null) ...[
            // The package resolves a CNSymbol against the SF Symbols the
            // running OS ships, and off Apple platforms there is no font on
            // the other side — so the Phosphor glyph stands in there, the way
            // every other CN caller in this app handles it.
            if (hasSFSymbols)
              CNIcon(symbol: CNSymbol(name, size: 17, color: palette.textMuted))
            else
              Icon(glyph, size: 17, color: palette.textMuted),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: onTapLabel == null
                ? text
                : GestureDetector(
                    onTap: onTapLabel,
                    behavior: HitTestBehavior.opaque,
                    child: text,
                  ),
          ),
          NativeSwitch(
            value: value,
            onChanged: onChanged,
            controller: controller,
          ),
        ],
      ),
    );
  }
}
