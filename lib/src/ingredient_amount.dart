/// Quantity parsing shared by the ingredient editor and save preflight.
/// Free-form amounts remain text and are never guessed into scaling quantities.
Map<String, dynamic> ingredientAmount(String input) {
  var text = input.trim();
  if (RegExp(r'^-\s*\d').hasMatch(text)) {
    throw const FormatException('Use an amount of zero or greater.');
  }
  const fractions = {
    '¼': '1/4',
    '½': '1/2',
    '¾': '3/4',
    '⅛': '1/8',
    '⅜': '3/8',
    '⅝': '5/8',
    '⅞': '7/8',
    '⅓': '1/3',
    '⅔': '2/3',
  };
  for (final entry in fractions.entries) {
    text = text.replaceAllMapped(
      RegExp('([0-9]?)${entry.key}'),
      (m) => '${m[1]!.isEmpty ? '' : '${m[1]} '}${entry.value}',
    );
  }
  final result = <String, dynamic>{
    'quantity_text': text.isEmpty ? null : text,
    'quantity_decimal': null,
    'quantity_numerator': null,
    'quantity_denominator': null,
    'quantity_max_decimal': null,
  };
  final fraction = RegExp(r'^(?:(\d+)\s+)?(\d+)\s*/\s*(\d+)$').firstMatch(text);
  if (fraction != null) {
    final denominator = int.parse(fraction[3]!);
    if (denominator == 0) {
      throw const FormatException(
        'A fraction must have a denominator greater than zero.',
      );
    }
    result['quantity_numerator'] =
        int.parse(fraction[2]!) +
        (int.tryParse(fraction[1] ?? '') ?? 0) * denominator;
    result['quantity_denominator'] = denominator;
  } else if (RegExp(r'^(?:\d+(?:\.\d+)?|\.\d+)$').hasMatch(text)) {
    result['quantity_decimal'] = double.parse(text);
  } else {
    final range = RegExp(r'^(\d*\.?\d+)\s*(?:–|-|to)\s*(\d*\.?\d+)$')
        .firstMatch(text);
    if (range != null) {
      final low = double.parse(range[1]!), high = double.parse(range[2]!);
      if (high < low) {
        throw const FormatException(
          'The end of the range must be at least the starting amount.',
        );
      }
      result['quantity_decimal'] = low;
      result['quantity_max_decimal'] = high;
    } else if (text.contains('/') && RegExp(r'^\d[\d\s/]*$').hasMatch(text)) {
      throw const FormatException('Use a fraction such as 1/4 or 1 1/2.');
    }
  }
  return result;
}

String ingredientAmountText(Map<String, dynamic> row) {
  var text = '${row['quantity_text'] ?? ''}'.trim();
  final unit = '${row['original_unit'] ?? ''}'.trim();
  if (unit.isNotEmpty &&
      text.toLowerCase().endsWith(' ${unit.toLowerCase()}')) {
    text = text.substring(0, text.length - unit.length).trim();
  }
  if (text.isNotEmpty) return text;
  final n = num.tryParse('${row['quantity_numerator']}');
  final d = num.tryParse('${row['quantity_denominator']}');
  if (n != null && d != null && d > 0) return '${n.toInt()}/${d.toInt()}';
  final decimal = row['quantity_decimal'];
  if (decimal != null) {
    return '$decimal${row['quantity_max_decimal'] == null ? '' : '–${row['quantity_max_decimal']}'}';
  }
  return '';
}

void applyIngredientFields(
  Map<String, dynamic> row,
  String amount,
  String unit,
  String name,
  String preparation,
) {
  row.addAll(ingredientAmount(amount));
  row['original_unit'] = unit.trim().isEmpty ? null : unit.trim();
  row['ingredient_name'] = name.trim();
  row['preparation'] = preparation.trim().isEmpty ? null : preparation.trim();
  row['original_text'] =
      [
        amount.trim(),
        unit.trim(),
        name.trim(),
      ].where((s) => s.isNotEmpty).join(' ') +
      (preparation.trim().isEmpty ? '' : ', ${preparation.trim()}');
  // A manually changed unit cannot retain an unrelated normalized unit code.
  row['unit_code'] = null;
}

Map<String, dynamic> ingredientEditingFields(Map<String, dynamic> row) {
  var amount = ingredientAmountText(row),
      unit = '${row['original_unit'] ?? ''}';
  if (unit.isEmpty) {
    final match = RegExp(
      r'^(\d+(?:\.\d+)?(?:\s+\d+/\d+|/\d+)?|\.\d+)\s+(cups?|tablespoons?|teaspoons?|tbsp|tsp|pounds?|ounces?|grams?|kg|ml|liters?)\b',
      caseSensitive: false,
    ).firstMatch('${row['original_text'] ?? ''}');
    if (match != null) {
      if (amount.isEmpty) amount = match[1]!;
      unit = match[2]!;
    }
  }
  return {
    'amount': amount,
    'unit': unit,
    'name': row['ingredient_name'],
    'preparation': row['preparation'],
  };
}
