import 'child_mode.dart';

import 'package:flutter/material.dart';

import 'recipe_browser.dart';
import 'recipe_import.dart';

/// Presentation for a saved recipe that has no cooking content yet.
class BlankRecipeDetail extends StatelessWidget {
  const BlankRecipeDetail({
    super.key,
    required this.title,
    required this.photos,
    required this.favorite,
    this.favoriteNames = '',
    this.onFavorite,
    this.onHouseholdFavorites,
    this.onPicture,
    this.onImport,
    this.onAttach,
    this.onMealPlan,
    this.offline = false,
    this.showFavorite = false,
  });
  final String title;
  final List<Map<String, dynamic>> photos;
  final bool favorite;
  final String favoriteNames;
  final VoidCallback? onFavorite,
      onHouseholdFavorites,
      onPicture,
      onAttach,
      onMealPlan;
  final ValueChanged<String>? onImport;
  final bool offline;
  final bool showFavorite;

  @override
  Widget build(BuildContext context) {
    childModeOf(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (showFavorite ||
                    onFavorite != null ||
                    onHouseholdFavorites != null)
                  IconButton(
                    tooltip: 'Favorite (hold for household)',
                    onPressed: onFavorite,
                    onLongPress: onHouseholdFavorites,
                    icon: Icon(
                      favorite ? Icons.favorite : Icons.favorite_border,
                    ),
                  ),
              ],
            ),
            if (favoriteNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Favorite of $favoriteNames',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (photos.isEmpty)
              Container(
                key: const ValueKey('blank-recipe-picture'),
                height: 148,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .045),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.photo_outlined,
                      size: 36,
                      color: colors.primary.withValues(alpha: .65),
                    ),
                    const SizedBox(height: 6),
                    if (!childMode.value && onPicture != null)
                      TextButton(
                        onPressed: childMode.value ? null : onPicture,
                        child: const Text('Add picture'),
                      )
                    else
                      Text('No picture', style: theme.textTheme.bodyMedium),
                  ],
                ),
              )
            else
              Card(
                key: const ValueKey('blank-recipe-picture'),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RecipePhotoGallery(photos: photos),
                      if (!childMode.value && onPicture != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: childMode.value ? null : onPicture,
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit picture'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (!childMode.value && onMealPlan != null)
              TextButton.icon(
                onPressed: childMode.value ? null : onMealPlan,
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Add to meal plan'),
              ),
            if (!childMode.value && onAttach != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: childMode.value ? null : onAttach,
                icon: const Icon(Icons.add),
                label: const Text('Add to my household'),
              ),
            ],
            if (!childMode.value && onImport != null) ...[
              const SizedBox(height: 20),
              Card(
                key: const ValueKey('blank-recipe-import'),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Import recipe',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      RecipeImportChoices(
                        actionButtons: true,
                        enabled: !offline && !childMode.value,
                        onSelected: onImport!,
                      ),
                      if (offline) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Connect to the internet to import.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
