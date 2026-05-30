import 'package:convert_the_spire_reborn/src/vault/db/database.dart';
import 'package:convert_the_spire_reborn/src/vault/models/conversation.dart';
import 'package:sqflite/sqflite.dart';

class ConversationDao {
  ConversationDao._();

  static final ConversationDao instance = ConversationDao._();

  Future<Database> get _db async => await AppDatabase.instance.database;

  Future<void> insertConversation(Conversation conversation) async {
    final db = await _db;
    await db.insert(
      'conversations',
      conversation.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Conversation?> getConversationById(String id) async {
    final db = await _db;
    final rows = await db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Conversation.fromMap(rows.first);
  }

  Future<Conversation?> findByParticipants(String userA, String userB) async {
    final sorted = [userA.trim(), userB.trim()]..sort();
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT * FROM conversations WHERE (participant1_id = ? AND participant2_id = ?) OR (participant1_id = ? AND participant2_id = ?) LIMIT 1',
      [sorted[0], sorted[1], sorted[1], sorted[0]],
    );
    if (rows.isEmpty) return null;
    return Conversation.fromMap(rows.first);
  }

  Future<List<Conversation>> getConversationsFor(String userId) async {
    final db = await _db;
    final rows = await db.query(
      'conversations',
      where: 'participant1_id = ? OR participant2_id = ?',
      whereArgs: [userId, userId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => Conversation.fromMap(r)).toList();
  }

  Future<void> deleteConversation(String id) async {
    final db = await _db;
    await db.delete('conversations', where: 'id = ?', whereArgs: [id]);
  }
}
