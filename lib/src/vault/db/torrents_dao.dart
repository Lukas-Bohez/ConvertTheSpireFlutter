import 'package:convert_the_spire_reborn/src/vault/db/database.dart';
import 'package:convert_the_spire_reborn/src/vault/models/torrent.dart';
import 'package:sqflite/sqflite.dart';

class TorrentsDao {
  TorrentsDao._();

  static final TorrentsDao instance = TorrentsDao._();

  Future<Database> get _db async => await AppDatabase.instance.database;

  Future<void> insertTorrent(TorrentModel torrent) async {
    final db = await _db;
    await db.insert(
      'torrents',
      torrent.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TorrentModel?> getTorrentById(String id) async {
    final db = await _db;
    final maps = await db.query(
      'torrents',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TorrentModel.fromMap(maps.first);
  }

  Future<List<TorrentModel>> getAllTorrents() async {
    final db = await _db;
    final maps = await db.query('torrents', orderBy: 'added_at DESC');
    return maps.map((m) => TorrentModel.fromMap(m)).toList();
  }

  Future<void> updateTorrent(TorrentModel torrent) async {
    final db = await _db;
    await db.update(
      'torrents',
      torrent.toMap(),
      where: 'id = ?',
      whereArgs: [torrent.id],
    );
  }

  /// Writes only [values] (column: value) of torrent [id].
  ///
  /// Status, seeding limit and the regular progress save used to read the
  /// whole row and write all of it back. Two of them at once undid each
  /// other: a status change could put back an older seeded total, or drop
  /// a seeding limit written a moment before.
  Future<void> updateFields(String id, Map<String, Object?> values) async {
    final db = await _db;
    await db.update('torrents', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTorrent(String id) async {
    final db = await _db;
    await db.delete('torrents', where: 'id = ?', whereArgs: [id]);
  }
}
