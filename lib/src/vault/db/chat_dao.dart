import 'package:sqflite/sqflite.dart';
import 'package:convert_the_spire_reborn/src/vault/db/database.dart';
import 'package:convert_the_spire_reborn/src/vault/models/chat_message.dart';

class ChatDao {
  ChatDao._();

  static final ChatDao instance = ChatDao._();

  Future<Database> get _db async => await AppDatabase.instance.database;

  Future<void> insertChatMessage(ChatMessage message) async {
    final db = await _db;
    await db.insert(
      'chat_messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ChatMessage>> getMessagesFor(
    String serverId,
    String channelId,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'chat_messages',
      where: 'server_id = ? AND channel_id = ?',
      whereArgs: [serverId, channelId],
      orderBy: 'timestamp ASC',
    );
    return rows.map((r) => ChatMessage.fromMap(r)).toList();
  }

  Future<ChatMessage?> getMessageById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'chat_messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatMessage.fromMap(rows.first);
  }

  Future<void> deleteMessage(String id) async {
    final db = await _db;
    await db.delete('chat_messages', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateMessage(ChatMessage message) async {
    final db = await _db;
    await db.update(
      'chat_messages',
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }
}
