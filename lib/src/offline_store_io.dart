import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _file(String key) async {
  final directory = await getApplicationSupportDirectory();
  final name = Uri.encodeComponent(key);
  return File('${directory.path}/recipes-$name.json');
}

Future<String?> readOfflineStore(String key) async {
  final file = await _file(key);
  return await file.exists() ? file.readAsString() : null;
}

Future<void> writeOfflineStore(String key, String value) async {
  final file = await _file(key);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(value, flush: true);
  await temporary.rename(file.path);
}
