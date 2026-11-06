import 'dart:ffi';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void initializeSqlite() {
  open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
}
final sqliteFactory = createDatabaseFactoryFfi(ffiInit:initializeSqlite);
