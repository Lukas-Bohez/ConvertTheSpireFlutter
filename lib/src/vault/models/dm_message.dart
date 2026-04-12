class DmMessage {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final DateTime timestamp;
  final bool isRead;

  DmMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.timestamp,
    this.isRead = false,
  });

  DmMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return DmMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'conversation_id': conversationId,
    'sender_id': senderId,
    'content': content,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'is_read': isRead ? 1 : 0,
  };

  factory DmMessage.fromMap(Map<String, dynamic> m) {
    return DmMessage(
      id: m['id'] as String,
      conversationId: m['conversation_id'] as String,
      senderId: m['sender_id'] as String,
      content: m['content'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
      isRead: (m['is_read'] as int? ?? 0) == 1,
    );
  }
}
