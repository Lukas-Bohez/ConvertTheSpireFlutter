enum UserStatus { online, offline, away }

String userStatusToString(UserStatus status) {
  return status.name;
}

UserStatus userStatusFromString(String value) {
  switch (value) {
    case 'online':
      return UserStatus.online;
    case 'away':
      return UserStatus.away;
    default:
      return UserStatus.offline;
  }
}

class ChatUser {
  final String id;
  final String username;
  final UserStatus status;
  final DateTime lastSeen;

  ChatUser({
    required this.id,
    required this.username,
    required this.status,
    required this.lastSeen,
  });

  factory ChatUser.fromMap(Map<String, dynamic> m) {
    return ChatUser(
      id: m['id'] as String,
      username: m['username'] as String,
      status: userStatusFromString(m['status'] as String? ?? 'offline'),
      lastSeen: DateTime.fromMillisecondsSinceEpoch(m['last_seen'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'status': userStatusToString(status),
      'last_seen': lastSeen.millisecondsSinceEpoch,
    };
  }

  ChatUser copyWith({
    String? id,
    String? username,
    UserStatus? status,
    DateTime? lastSeen,
  }) {
    return ChatUser(
      id: id ?? this.id,
      username: username ?? this.username,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
