import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/food_models.dart';
import '../../../providers/nutrition_providers.dart';
import '../../components/components.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ph_light_icons.dart';
import '../../widgets/status_card.dart';
import 'food_result_tile.dart';

/// The database search field, shared by the search screen and the recipe
/// builder's ingredient picker so both debounce and render results the
/// same way.
class FoodSearchField extends ConsumerStatefulWidget {
  const FoodSearchField({super.key, this.autofocus = false});

  final bool autofocus;

  @override
  ConsumerState<FoodSearchField> createState() => _FoodSearchFieldState();
}

class _FoodSearchFieldState extends ConsumerState<FoodSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(foodSearchQueryProvider));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // Watched, not read: the clear button appears and disappears with the
    // query, and nothing else would rebuild this field as it is typed in.
    final query = ref.watch(foodSearchQueryProvider);

    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      onChanged: ref.read(foodSearchQueryProvider.notifier).set,
      decoration: appInputDecoration(
        context,
        hint: 'Search foods and brands',
        prefixIcon:
            Icon(PhLight.magnifyingGlass, size: 17, color: palette.textMuted),
        suffixIcon: query.isEmpty
            ? null
            : Semantics(
                button: true,
                label: 'Clear search',
                child: GestureDetector(
                  onTap: () {
                    _controller.clear();
                    ref.read(foodSearchQueryProvider.notifier).set('');
                  },
                  child: Icon(PhLight.xCircle, size: 17, color: palette.textMuted),
                ),
              ),
      ),
      style: context.typography.ui(size: 15),
    );
  }
}

/// The result list for whatever is currently in [FoodSearchField].
///
/// Renders its own loading, error and empty states, so both callers get
/// the same behaviour without repeating the `when`.
class FoodSearchResults extends ConsumerWidget {
  const FoodSearchResults({super.key, required this.onSelect});

  final ValueChanged<FoodSearchHit> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final query = ref.watch(foodSearchQueryProvider).trim();

    if (query.length < foodSearchMinLength) {
      return _Hint(
        message: 'Type at least $foodSearchMinLength letters to search the '
            'food database.',
      );
    }

    return ref.watch(foodSearchProvider).when(
          data: (hits) {
            if (hits.isEmpty) {
              return _Hint(message: 'Nothing in the database matches "$query".');
            }
            return Column(
              children: [
                for (var i = 0; i < hits.length; i++) ...[
                  FoodResultTile(hit: hits[i], onTap: () => onSelect(hits[i])),
                  if (i < hits.length - 1) const SizedBox(height: 8),
                ],
              ],
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: CircularProgressIndicator(
                color: palette.accent,
                strokeWidth: 2.5,
              ),
            ),
          ),
          error: (error, _) => StatusCard(
            message: error.toString(),
            tone: StatusTone.error,
          ),
        );
  }
}

/// The quiet line shown in place of results — before a query is long
/// enough, and when one returns nothing.
class _Hint extends StatelessWidget {
  const _Hint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Column(
        children: [
          Icon(PhLight.magnifyingGlass, size: 26, color: palette.textMuted),
          const SizedBox(height: 14),
          Text(
            message,
            textAlign: TextAlign.center,
            style: context.typography.ui(
              size: 13,
              color: palette.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
