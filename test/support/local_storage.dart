import 'package:coffey_table_recipes/src/local_sqlite.dart';

import 'sqlite.dart';

// Widget/native tests use immediate storage; real SQLite persistence is checked separately.
class MemoryLocalStorage extends LocalSqlite {
  MemoryLocalStorage() : super(factory: sqliteFactory);
  final values = <String, String>{};
  @override
  Future<String?> read(String owner) async => values[owner];
  @override
  Future<void> write(String owner, String text) async {
    values[owner] = text;
  }
}
