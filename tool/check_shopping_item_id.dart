import 'package:coffey_table_recipes/src/shopping_item_id.dart';

// Compile to JavaScript and run with Node as well as checking on the Dart VM.
void main() {
  final ids = <String>{};
  for (var i = 0; i < 1000; i++) {
    final id = newShoppingItemId();
    if (!RegExp(r'^[0-9]+_[0-9]+$').hasMatch(id) ||
        id.length > 80 ||
        !ids.add(id)) {
      throw StateError('Invalid or repeated shopping item ID');
    }
  }
  // ignore: avoid_print
  print('Shopping item IDs: 1000 valid unique IDs');
}
