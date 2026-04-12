import 'package:sqflite/sqflite.dart';
import 'package:convert_the_spire_reborn/src/vault/db/database.dart';
import 'package:convert_the_spire_reborn/src/vault/models/dm_message.dart';

class DmMessagesDao {
  DmMessagesDao._();

  static final DmMessagesDao instance = DmMessagesDao._();

  Future<Database> get _db async => await AppDatabase.instance.database;

  Future<void> insertMessage(DmMessage message) async {
    final db = await _db;
    await db.insert(
      'dm_messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DmMessage>> getMessagesForConversation(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'dm_messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'timestamp ASC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => DmMessage.fromMap(r)).toList();
  }

  Future<List<DmMessage>> getUnreadMessages(String userId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT m.* FROM dm_messages m
      INNER JOIN conversations c ON c.id = m.conversation_id
      WHERE m.is_read = 0 AND m.sender_id != ? AND (c.participant1_id = ? OR c.participant2_id = ?)
      ''',
      [userId, userId, userId],
    );
    return rows.map((r) => DmMessage.fromMap(r)).toList();
  }

  Future<void> markConversationRead(
    String conversationId,
    String readerId,
  ) async {
    final db = await _db;
    await db.update(
      'dm_messages',
      {'is_read': 1},
      where: 'conversation_id = ? AND sender_id != ?',
      whereArgs: [conversationId, readerId],
    );
  }

  Future<void> markMessageRead(String messageId) async {
    final db = await _db;
    await db.update(
      'dm_messages',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<DmMessage?> getMessageById(String messageId) async {
    final db = await _db;
    final rows = await db.query(
      'dm_messages',
      where: 'id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DmMessage.fromMap(rows.first);
  }

  Future<void> updateMessage(DmMessage message) async {
    final db = await _db;
    await db.update(
      'dm_messages',
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await _db;
    await db.delete('dm_messages', where: 'id = ?', whereArgs: [messageId]);
  }

  Future<int> getUnreadCountForConversation(
    String conversationId,
    String userId,
  ) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM dm_messages WHERE conversation_id = ? AND sender_id != ? AND is_read = 0',
      [conversationId, userId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
