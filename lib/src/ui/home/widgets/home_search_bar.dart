import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';

/// Where a query goes when it is submitted.
enum SearchMode {
  milo,
  chrome;

  String get label {
    switch (this) {
      case SearchMode.milo:
        return 'Search with Milo';
      case SearchMode.chrome:
        return 'Search on Chrome';
    }
  }
}

/// The pill under the welcome header.
///
/// The mode lives here rather than in a provider: nothing outside this widget
/// reads it yet, and [onSubmitted] hands the caller both halves when there is
/// somewhere to send them.
class HomeSearchBar extends StatefulWidget {
  const HomeSearchBar({super.key, this.onSubmitted});

  final void Function(String query, SearchMode mode)? onSubmitted;

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  final _controller = TextEditingController();
  SearchMode _mode = SearchMode.milo;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: palette.glassBorder),
      ),
      child: Row(
        children: [
          Icon(PhLight.magnifyingGlass, size: 19, color: palette.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: (value) =>
                  widget.onSubmitted?.call(value, _mode),
              style: context.typography.ui(size: 15, color: palette.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search..',
                hintStyle:
                    context.typography.ui(size: 15, color: palette.textMuted),
              ),
            ),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<SearchMode>(
            initialValue: _mode,
            tooltip: 'Where to search',
            color: palette.surfaceRaised,
            position: PopupMenuPosition.under,
            onSelected: (mode) => setState(() => _mode = mode),
            itemBuilder: (context) => [
              for (final mode in SearchMode.values)
                PopupMenuItem(
                  value: mode,
                  child: Text(
                    mode.label,
                    style: context.typography
                        .ui(size: 14, color: palette.textPrimary),
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhLight.caretDown, size: 15, color: palette.textMuted),
                const SizedBox(width: 7),
                Text(
                  _mode.label,
                  style: context.typography.ui(
                    size: 13.5,
                    weight: FontWeight.w600,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
