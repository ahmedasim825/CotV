import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// The `+` at the bottom of the Today card, and the field it becomes.
///
/// Tapping it swaps the button for a text field in the same slot and focuses
/// it, which is what opens the keyboard. Enter commits and focus is requested
/// straight back, so a list can be typed in one go the way iOS Reminders
/// behaves. Escape, or leaving it empty, collapses it back to the button.
///
/// Deliberately not a route to the form sheet: the sheet is still there behind
/// a tap on any row, for the fields this row has no room for. This control is
/// the fast path, and a fast path that opens a modal is not one.
class InlineAddRow extends StatefulWidget {
  const InlineAddRow({
    super.key,
    required this.hint,
    required this.semanticLabel,
    required this.onSubmit,
    required this.onOpenDetails,
  });

  final String hint;
  final String semanticLabel;

  /// Called with the trimmed, non-empty title.
  final ValueChanged<String> onSubmit;

  /// Called from the ⓘ with whatever is in the field, trimmed, to carry it
  /// into the sheet. The row is left open and untouched: the sheet may be
  /// dismissed, and a control that emptied the field on the way out would
  /// lose what was typed.
  final ValueChanged<String> onOpenDetails;

  @override
  State<InlineAddRow> createState() => _InlineAddRowState();
}

class _InlineAddRowState extends State<InlineAddRow> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_handleFocusChange);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    // Collapse on blur, but only with nothing typed. Losing focus mid-entry —
    // to a system sheet, or a scroll that steals it — must not discard what
    // is in the field.
    if (!_focus.hasFocus && _controller.text.trim().isEmpty && _isOpen) {
      setState(() => _isOpen = false);
    }
  }

  void _open() {
    setState(() => _isOpen = true);
    _focus.requestFocus();
  }

  void _close() {
    _controller.clear();
    setState(() => _isOpen = false);
    _focus.unfocus();
  }

  void _submit(String raw) {
    final title = raw.trim();
    if (title.isEmpty) {
      _close();
      return;
    }
    widget.onSubmit(title);
    _controller.clear();
    // Kept open and focused: adding one item is usually adding several, and
    // re-tapping `+` between each is the friction this control exists to
    // remove.
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: _isOpen
          ? Row(
              children: [
                _Glyph(icon: PhLight.plus, palette: palette),
                const SizedBox(width: 10),
                Expanded(
                  child: Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.escape):
                          DismissIntent(),
                    },
                    child: Actions(
                      actions: {
                        DismissIntent: CallbackAction<DismissIntent>(
                          onInvoke: (_) {
                            _close();
                            return null;
                          },
                        ),
                      },
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: _submit,
                        style: context.typography.ui(
                          size: 16,
                          weight: FontWeight.w500,
                          height: 1.3,
                        ),
                        cursorColor: palette.accent,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: widget.hint,
                          hintStyle: context.typography.ui(
                            size: 16,
                            weight: FontWeight.w500,
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InfoButton(
                  palette: palette,
                  onTap: () => widget.onOpenDetails(_controller.text.trim()),
                ),
              ],
            )
          : Semantics(
              button: true,
              // Explicitly its own node. The collapsed control is a glyph and
              // an empty gap — nothing in the subtree carries text for this
              // annotation to attach to, so without `container` the label has
              // nowhere to land and a screen reader reads an unlabelled tap
              // target.
              container: true,
              label: widget.semanticLabel,
              child: GestureDetector(
                onTap: _open,
                behavior: HitTestBehavior.opaque,
                // Full-width hit area so the tap target is the row, not just
                // the 28pt glyph at its start.
                child: Row(
                  children: [
                    _Glyph(icon: PhLight.plus, palette: palette),
                    const Expanded(child: SizedBox(height: 28)),
                  ],
                ),
              ),
            ),
    );
  }
}

/// The ⓘ at the end of the open add row.
///
/// Opens the task sheet on whatever is typed so far: this row is the fast
/// path, and the ⓘ is the way out of it when a line needs a date, a note or a
/// link that the row has no space to ask for.
class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.palette, required this.onTap});

  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Task details',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Icon(PhLight.info, size: 16, color: palette.textMuted),
          ),
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.palette});

  final IconData icon;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.checkboxFill,
        // A circle, matching the completion boxes it sits under: the add
        // control is another mark in the same column, not a different kind
        // of thing.
        shape: BoxShape.circle,
        border: Border.all(color: palette.bentoBorder),
      ),
      child: Icon(icon, size: 14, color: palette.textSecondary),
    );
  }
}
