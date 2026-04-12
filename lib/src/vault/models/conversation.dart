class Conversation {
  final String id;
  final String participant1Id;
  final String participant2Id;
  final DateTime createdAt;

  Conversation({
    required this.id,
    required this.participant1Id,
    required this.participant2Id,
    required this.createdAt,
  });

  bool involves(String userId) {
    return participant1Id == userId || participant2Id == userId;
  }

  bool pairMatches(String userA, String userB) {
    final pair = [participant1Id, participant2Id]..sort();
    final query = [userA, userB]..sort();
    return pair[0] == query[0] && pair[1] == query[1];
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'participant1_id': participant1Id,
      'participant2_id': participant2Id,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> m) {
    return Conversation(
      id: m['id'] as String,
      participant1Id: m['participant1_id'] as String,
      participant2Id: m['participant2_id'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    );
  }
}
