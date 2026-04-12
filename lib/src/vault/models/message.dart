class MessageModel {
  final String id;
  final String sender;
  final String recipient;
  final String body;
  final int createdAt;
  final bool isSent;
  final String protocol;

  MessageModel({
    required this.id,
    required this.sender,
    required this.recipient,
    required this.body,
    required this.createdAt,
    this.isSent = false,
    this.protocol = 'local',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender': sender,
      'recipient': recipient,
      'body': body,
      'created_at': createdAt,
      'is_sent': isSent ? 1 : 0,
      'protocol': protocol,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      sender: map['sender'] as String,
      recipient: map['recipient'] as String,
      body: map['body'] as String,
      createdAt: map['created_at'] as int,
      isSent: (map['is_sent'] as int? ?? 0) == 1,
      protocol: map['protocol'] as String? ?? 'local',
    );
  }
}
