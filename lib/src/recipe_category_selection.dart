/// Keep an existing selection distinct from an unsaved category proposal.
void normalizeRecipeCategory(
  Map<String, dynamic> row,
  List<Map<String, dynamic>> catalog,
) {
  String key(Object? value) => '${value ?? ''}'.trim().toLowerCase();
  Map<String, dynamic>? selected;
  for (final category in catalog) {
    if (row['category_id'] != null &&
        '${category['id']}' == '${row['category_id']}') {
      selected = category;
      break;
    }
  }
  if (selected == null && row['label'] != null) {
    final label = key(row['label']);
    final parent = key(row['parent_label']);
    for (final category in catalog) {
      if (key(category['label']) == label &&
          (key(category['parent_label']) == parent ||
              (label == parent && category['parent_label'] == null))) {
        selected = category;
        break;
      }
    }
  }
  if (selected != null) {
    row['category_id'] = '${selected['id']}';
    row['_parent_category'] = selected['parent_label'] ?? selected['label'];
    row.remove('label');
    row.remove('parent_label');
    row.remove('_new_category');
  }
}

/// Choosing a parent explicitly selects that existing root until a child is chosen.
void selectRecipeCategoryParent(
  Map<String, dynamic> row,
  List<Map<String, dynamic>> catalog,
) {
  final parent = row['_parent_category'];
  row.remove('category_id');
  row.remove('label');
  row.remove('parent_label');
  row.remove('_new_category');
  for (final category in catalog) {
    if (category['parent_label'] == null && category['label'] == parent) {
      row['category_id'] = '${category['id']}';
      break;
    }
  }
}
