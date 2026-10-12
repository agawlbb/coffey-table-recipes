int? recipeSeconds(Object? value) {
  final number = num.tryParse('$value');
  if (number == null || !number.isFinite || number < 0) return null;
  return number.round();
}

String formatRecipeTime(Object? seconds, {bool clock = false}) {
  final total = recipeSeconds(seconds) ?? 0;
  final hours = total ~/ 3600;
  final minutes = (total ~/ 60) % 60;
  final remainder = total % 60;
  if (clock) {
    final tail =
        '${minutes.toString().padLeft(hours > 0 ? 2 : 1, '0')}:${remainder.toString().padLeft(2, '0')}';
    return hours > 0 ? '$hours:$tail' : tail;
  }
  final parts = <String>[
    if (hours > 0) '$hours hr',
    if (minutes > 0 || hours == 0) '$minutes min',
    if (remainder > 0) '$remainder sec',
  ];
  return parts.join(' ');
}

/// Timed actions accept m:ss or h:mm:ss. Metadata accepts h:mm (whole minutes).
int? parseRecipeTime(String text, {bool minutePrecision = false}) {
  final parts = text.trim().split(':');
  if (parts.length < 2 || parts.length > (minutePrecision ? 2 : 3)) return null;
  if (parts.any((part) => !RegExp(r'^\d+$').hasMatch(part))) return null;
  final parsed = parts.map(int.tryParse).toList();
  if (parsed.any((value) => value == null)) return null;
  final values = parsed.cast<int>();
  if (values.skip(1).any((value) => value >= 60)) return null;
  if (minutePrecision) return values[0] * 60 + values[1];
  return parts.length == 2
      ? values[0] * 60 + values[1]
      : values[0] * 3600 + values[1] * 60 + values[2];
}

String recipeTimeInput(Object? value, {bool minutePrecision = false}) {
  final amount = recipeSeconds(value);
  if (amount == null) return '';
  if (minutePrecision) {
    return '${amount ~/ 60}:${(amount % 60).toString().padLeft(2, '0')}';
  }
  return formatRecipeTime(amount, clock: true);
}
