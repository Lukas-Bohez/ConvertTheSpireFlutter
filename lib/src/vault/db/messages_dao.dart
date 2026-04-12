import 'package:sqflite/sqflite.dart';
import 'package:convert_the_spire_reborn/src/vault/db/database.dart';
import 'package:convert_the_spire_reborn/src/vault/models/message.dart';

class MessagesDao {
  MessagesDao._();

  static final MessagesDao instance = MessagesDao._();

  Future<Database> get _db async => await AppDatabase.instance.database;

  Future<void> insertMessage(MessageModel message) async {
    final db = await _db;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MessageModel>> getAllMessages() async {
    final db = await _db;
    final rows = await db.query('messages', orderBy: 'created_at DESC');
    return rows.map((r) => MessageModel.fromMap(r)).toList();
  }

  Future<void> markMessageAsSent(String id) async {
    final db = await _db;
    await db.update(
      'messages',
      {'is_sent': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMessage(String id) async {
    final db = await _db;
    await db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }
}
