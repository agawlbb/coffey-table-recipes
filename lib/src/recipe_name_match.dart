/// Conservative title matching for a warning, never a uniqueness constraint.
bool similarRecipeNames(String first, String second) {
  String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  final a = normalize(first), b = normalize(second);
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  final wordsA = a.split(' ').toSet(), wordsB = b.split(' ').toSet();
  if (wordsA.length > 1 &&
      wordsB.length > 1 &&
      wordsA.intersection(wordsB).length / wordsA.union(wordsB).length >= .8) {
    return true;
  }
  // Short names need exact matches to avoid warnings such as Rice / Ribs.
  if (a.length < 8 || b.length < 8) return false;
  var previous = List.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      final values = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      ];
      current.add(values.reduce((x, y) => x < y ? x : y));
    }
    previous = current;
  }
  return previous.last / (a.length > b.length ? a.length : b.length) <= .12;
}
