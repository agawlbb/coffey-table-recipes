import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'offline_store.dart';

/// The app's local data and unsent changes are committed together.
class LocalSqlite {
  LocalSqlite({
    DatabaseFactory? factory,
    this.path = 'coffey-table.sqlite',
    this.readLegacy = readOfflineStore,
  }) : factory = factory ?? databaseFactory;
  final DatabaseFactory factory;
  final String path;
  final Future<String?> Function(String) readLegacy;
  Future<Database>? _opening;
  Future<Database> get database => _opening ??= () async {
    final directory = await factory.getDatabasesPath();
    return factory.openDatabase(
      path.startsWith('/') ? path : '$directory/$path',
      options: OpenDatabaseOptions(
        onOpen: (db) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS stores (owner TEXT PRIMARY KEY)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS resources (owner TEXT, path TEXT, value TEXT, PRIMARY KEY(owner,path))',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS changes (owner TEXT, id TEXT, value TEXT, PRIMARY KEY(owner,id))',
          );
        },
      ),
    );
  }();

  Future<String?> read(String owner) async {
    final db = await database;
    final exists = await db.query(
      'stores',
      where: 'owner=?',
      whereArgs: [owner],
    );
    if (exists.isEmpty) {
      final old = await readLegacy(owner);
      final state = old == null
          ? <String, dynamic>{'data': {}}
          : Map<String, dynamic>.from(jsonDecode(old) as Map);
      final account = owner.replaceFirst('local-first-v1-', '');
      final actions = await readLegacy('offline-actions-$account');
      if (actions != null) {
        final pending = <Map<String, dynamic>>[];
        for (final old in jsonDecode(actions) as List) {
          final recipe = old['kind'] == 'recipe';
          pending.add({
            'id': old['id'],
            'path': old['path'],
            'body': recipe
                ? old['body']
                : {
                    'remove_ids': [old['item']],
                  },
            'review': recipe && old['create'] != true,
            if (recipe && old['create'] == true)
              'local_id': 'local-${old['id']}',
            if (!recipe)
              'expires':
                  (old['at'] as int) + const Duration(hours: 2).inMilliseconds,
          });
        }
        state['pending'] = pending;
      }
      await write(owner, jsonEncode(state));
      return jsonEncode(state);
    }
    final rows = await db.query(
      'resources',
      where: 'owner=?',
      whereArgs: [owner],
    );
    final changes = await db.query(
      'changes',
      where: 'owner=?',
      whereArgs: [owner],
      orderBy: 'rowid',
    );
    return jsonEncode({
      'data': {
        for (final row in rows)
          row['path'] as String: jsonDecode(row['value'] as String),
      },
      'pending': [
        for (final row in changes) jsonDecode(row['value'] as String),
      ],
    });
  }

  Future<void> write(String owner, String text) async {
    final state = jsonDecode(text) as Map;
    final db = await database;
    await db.transaction((tx) async {
      await tx.insert('stores', {
        'owner': owner,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final existing = (await tx.query(
        'resources',
        columns: ['path'],
        where: 'owner=?',
        whereArgs: [owner],
      )).map((e) => e['path'] as String).toSet();
      await tx.delete('changes', where: 'owner=?', whereArgs: [owner]);
      final batch = tx.batch();
      for (final row in (state['data'] as Map).entries) {
        existing.remove(row.key);
        batch.rawInsert(
          'INSERT INTO resources(owner,path,value) VALUES(?,?,?) ON CONFLICT(owner,path) DO UPDATE SET value=excluded.value WHERE resources.value<>excluded.value',
          [owner, row.key, jsonEncode(row.value)],
        );
      }
      for (final path in existing) {
        batch.delete(
          'resources',
          where: 'owner=? AND path=?',
          whereArgs: [owner, path],
        );
      }
      for (final row in state['pending'] as List? ?? []) {
        batch.insert('changes', {
          'owner': owner,
          'id': row['id'],
          'value': jsonEncode(row),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> close() async {
    if (_opening != null) await (await _opening!).close();
    _opening = null;
  }
}

LocalSqlite? _localSqlite;
Future<String?> readLocalSqlite(String key) =>
    (_localSqlite ??= LocalSqlite()).read(key);
Future<void> writeLocalSqlite(String key, String text) =>
    (_localSqlite ??= LocalSqlite()).write(key, text);
