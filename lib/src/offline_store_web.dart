import 'dart:js_interop';

@JS('localStorage')
external _Storage get _storage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

Future<String?> readOfflineStore(String key) async =>
    _storage.getItem('recipes-$key');
Future<void> writeOfflineStore(String key, String value) async =>
    _storage.setItem('recipes-$key', value);
