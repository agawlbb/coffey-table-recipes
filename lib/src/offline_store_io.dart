import 'dart:io';

import 'package:path_provider/path_provider.dart';

class OfflineFileStore {
  OfflineFileStore({this.directory = getApplicationSupportDirectory});
  final Future<Directory> Function() directory;

  Future<File> _file(String key) async {
    final folder = await directory();
    final name = Uri.encodeComponent(key);
    return File('${folder.path}/recipes-$name.json');
  }

  Future<String?> read(String key) async {
    final file = await _file(key);
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> write(String key, String value) async {
    final file = await _file(key);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(value, flush: true);
    await temporary.rename(file.path);
  }
}

final _store = OfflineFileStore();
Future<String?> readOfflineStore(String key) => _store.read(key);
Future<void> writeOfflineStore(String key, String value) =>
    _store.write(key, value);
