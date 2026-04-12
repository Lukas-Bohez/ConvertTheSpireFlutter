class AiChatEntry {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final bool isAutoTriggered;
  final bool isStreaming;

  const AiChatEntry({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isAutoTriggered = false,
    this.isStreaming = false,
  });

  bool get isAuto => isAutoTriggered;

  AiChatEntry copyWith({String? content, bool? isStreaming}) {
    return AiChatEntry(
      id: id,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      isAutoTriggered: isAutoTriggered,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
