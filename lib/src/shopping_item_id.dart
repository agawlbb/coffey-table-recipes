import 'dart:math';

String newShoppingItemId() {
  // Use a literal: web integer shifts truncate `1 << 32` to zero.
  final suffix = Random.secure().nextInt(0x100000000);
  return '${DateTime.now().microsecondsSinceEpoch}_$suffix';
}
