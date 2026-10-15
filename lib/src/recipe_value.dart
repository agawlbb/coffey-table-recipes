/// Removes decimal padding for display without rounding or changing stored values.
String recipeValue(Object? value) {
  if (value == null) return '';
  return value
      .toString()
      .replaceFirstMapped(RegExp(r'(\.\d*?[1-9])0+$'), (match) => match[1]!)
      .replaceFirst(RegExp(r'\.0+$'), '');
}
