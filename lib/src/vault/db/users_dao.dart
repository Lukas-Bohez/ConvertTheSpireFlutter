import 'package:convert_the_spire_reborn/src/vault/db/database.dart';
import 'package:convert_the_spire_reborn/src/vault/models/chat_user.dart';
import 'package:sqflite/sqflite.dart';

class UsersDao {
  UsersDao._();

  static final UsersDao instance = UsersDao._();

  Future<Database> get _db async => await AppDatabase.instance.database;

  Future<void> insertUser(ChatUser user) async {
    final db = await _db;
    await db.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ChatUser?> getUserById(String id) async {
    final db = await _db;
    final rows = await db.query('users', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ChatUser.fromMap(rows.first);
  }

  Future<ChatUser?> getUserByName(String username) async {
    final db = await _db;
    final rows = await db.query(
      'users',
      where: 'LOWER(username) = LOWER(?)',
      whereArgs: [username],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatUser.fromMap(rows.first);
  }

  Future<List<ChatUser>> getAllUsers() async {
    final db = await _db;
    final rows = await db.query('users');
    return rows.map((r) => ChatUser.fromMap(r)).toList();
  }

  Future<void> updateUser(ChatUser user) async {
    final db = await _db;
    await db.update(
      'users',
      user.toMap(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  Future<void> deleteUser(String id) async {
    final db = await _db;
    await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }
}
