import 'dart:js_interop';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external int get length;
  external String? key(int index);
  external void removeItem(String key);
  external void setItem(String key, String value);
}

Future<String?> readOfflineStore(String key) async =>
    _storage.getItem('recipes-$key');
Future<void> writeOfflineStore(String key, String value) async =>
    _storage.setItem('recipes-$key', value);

Future<void> clearOfflineStore() async {
  final keys = [for (var i = 0; i < _storage.length; i++) _storage.key(i)];
  for (final key in keys) {
    if (key != null && key.startsWith('recipes-')) _storage.removeItem(key);
  }
}
