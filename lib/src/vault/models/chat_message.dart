import 'dart:convert';

import 'package:convert_the_spire_reborn/src/utils/safe_json.dart';

class ChatMessage {
  final String id;
  final String serverId;
  final String channelId;
  final String author;
  final String text;
  final DateTime timestamp;
  final String? replyToMessageId;
  final DateTime? editedAt;
  final Map<String, int> reactions;

  ChatMessage({
    required this.id,
    required this.serverId,
    required this.channelId,
    required this.author,
    required this.text,
    required this.timestamp,
    this.replyToMessageId,
    this.editedAt,
    this.reactions = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'channel_id': channelId,
      'author': author,
      'text': text,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'edited_at': editedAt?.millisecondsSinceEpoch,
      'reply_to': replyToMessageId,
      'reactions': reactions.isNotEmpty ? jsonEncode(reactions) : null,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      serverId: map['server_id'] as String,
      channelId: map['channel_id'] as String,
      author: map['author'] as String,
      text: map['text'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      editedAt: map['edited_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['edited_at'] as int)
          : null,
      replyToMessageId: map['reply_to'] as String?,
      reactions: map['reactions'] != null
          ? (safeJsonDecode<Map<String, dynamic>>(map['reactions'] as String) ??
                  const <String, dynamic>{})
              .map((k, v) => MapEntry(k, v as int))
          : {},
    );
  }
}
