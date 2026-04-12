enum ChatHubEntryType { dm, serverChannel }

class ChatHubEntry {
  final String id;
  final ChatHubEntryType type;
  final String title;
  final String subtitle;
  final String serverId;
  final String channelId;
  final String conversationId;
  final int unread;
  final DateTime lastUpdated;

  ChatHubEntry({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle = '',
    this.serverId = '',
    this.channelId = '',
    this.conversationId = '',
    this.unread = 0,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  bool get isDM => type == ChatHubEntryType.dm;
  bool get isServerChannel => type == ChatHubEntryType.serverChannel;
}
