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
  });

  final String hint;
  final String semanticLabel;

  /// Called with the trimmed, non-empty title.
  final ValueChanged<String> onSubmit;

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
                          size: 13.5,
                          weight: FontWeight.w500,
                          height: 1.35,
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
                            size: 13.5,
                            weight: FontWeight.w500,
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.bentoBorder),
      ),
      child: Icon(icon, size: 14, color: palette.textSecondary),
    );
  }
}
