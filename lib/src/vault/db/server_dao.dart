import 'package:sqflite/sqflite.dart';
import 'package:convert_the_spire_reborn/src/vault/db/database.dart';
import 'package:convert_the_spire_reborn/src/vault/models/server.dart';

class ServerDao {
  ServerDao._();

  static final ServerDao instance = ServerDao._();

  Future<Database> get _db async => await AppDatabase.instance.database;

  Future<void> insertServer(ServerModel server) async {
    final db = await _db;
    await db.insert(
      'servers',
      server.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ServerModel>> getAllServers() async {
    final db = await _db;
    final rows = await db.query('servers', orderBy: 'name ASC');
    return rows.map((r) => ServerModel.fromMap(r)).toList();
  }

  Future<ServerModel?> getServerById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'servers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ServerModel.fromMap(rows.first);
  }

  Future<void> updateServer(ServerModel server) async {
    final db = await _db;
    await db.update(
      'servers',
      server.toMap(),
      where: 'id = ?',
      whereArgs: [server.id],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteServer(String id) async {
    final db = await _db;
    await db.delete('servers', where: 'id = ?', whereArgs: [id]);
  }
}
