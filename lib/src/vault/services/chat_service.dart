import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:convert_the_spire_reborn/src/vault/db/chat_dao.dart';
import 'package:convert_the_spire_reborn/src/vault/db/conversation_dao.dart';
import 'package:convert_the_spire_reborn/src/vault/db/dm_messages_dao.dart';
import 'package:convert_the_spire_reborn/src/vault/db/users_dao.dart';
import 'package:convert_the_spire_reborn/src/vault/models/chat_hub_entry.dart';
import 'package:convert_the_spire_reborn/src/vault/models/chat_message.dart';
import 'package:convert_the_spire_reborn/src/vault/services/server_service.dart';
import 'package:convert_the_spire_reborn/src/vault/models/chat_user.dart';
import 'package:convert_the_spire_reborn/src/vault/models/conversation.dart';
import 'package:convert_the_spire_reborn/src/vault/models/dm_message.dart';

class ChatService {
  ChatService._();

  static final ChatService instance = ChatService._();

  final _uuid = const Uuid();

  final Map<String, DateTime> _typingStatus = {};
  final Map<String, UserStatus> _presence = {};

  Future<ChatUser> _ensureUserExists(String username) async {
    final safeName = username.trim();
    if (safeName.isEmpty) {
      throw ArgumentError('Username cannot be empty');
    }
    final existing = await UsersDao.instance.getUserByName(safeName);
    if (existing != null) return existing;

    final user = ChatUser(
      id: _uuid.v4(),
      username: safeName,
      status: UserStatus.offline,
      lastSeen: DateTime.now(),
    );
    await UsersDao.instance.insertUser(user);
    return user;
  }

  Future<ChatUser?> getUser(String username) async {
    return await UsersDao.instance.getUserByName(username.trim());
  }

  Future<void> setUserStatus(String username, UserStatus status) async {
    final user = await _ensureUserExists(username);
    final updated = user.copyWith(status: status, lastSeen: DateTime.now());
    await UsersDao.instance.insertUser(updated);
    _presence[username] = status;

    _presence[username] = status;
  }

  bool isUserOnline(String username) {
    final status = _presence[username];
    return status == UserStatus.online;
  }

  Future<Conversation> getOrCreateConversation(String a, String b) async {
    if (a.trim().isEmpty || b.trim().isEmpty) {
      throw ArgumentError('Participant username cannot be empty');
    }

    final me = await _ensureUserExists(a);
    final peer = await _ensureUserExists(b);

    final existing = await ConversationDao.instance.findByParticipants(
      me.id,
      peer.id,
    );
    if (existing != null) return existing;

    final participants = [me.id, peer.id]..sort();
    final conversation = Conversation(
      id: _uuid.v4(),
      participant1Id: participants[0],
      participant2Id: participants[1],
      createdAt: DateTime.now(),
    );
    await ConversationDao.instance.insertConversation(conversation);
    return conversation;
  }

  Future<List<Conversation>> conversationsFor(String username) async {
    final user = await _ensureUserExists(username);
    return await ConversationDao.instance.getConversationsFor(user.id);
  }

  Future<List<DmMessage>> getConversationMessages(
    Conversation conversation, {
    int limit = 50,
    int offset = 0,
  }) async {
    return await DmMessagesDao.instance.getMessagesForConversation(
      conversation.id,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> markConversationRead(
    String conversationId,
    String readerUsername,
  ) async {
    final reader = await _ensureUserExists(readerUsername);
    final conv = await ConversationDao.instance.getConversationById(
      conversationId,
    );
    if (conv == null) throw StateError('Conversation not found');
    if (!conv.involves(reader.id)) {
      throw StateError('User cannot mark this conversation as read');
    }
    await DmMessagesDao.instance.markConversationRead(
      conversationId,
      reader.id,
    );
  }

  Future<void> sendDirectMessage(
    String from,
    String to,
    String content, {
    String? replyToMessageId,
  }) async {
    final cleanText = _sanitize(content);
    if (cleanText.isEmpty) {
      throw ArgumentError('Message cannot be empty');
    }

    final sender = await _ensureUserExists(from);
    final recipient = await _ensureUserExists(to);

    final conversation = await getOrCreateConversation(from, to);

    final message = DmMessage(
      id: _uuid.v4(),
      conversationId: conversation.id,
      senderId: sender.id,
      content: cleanText,
      timestamp: DateTime.now(),
      isRead: false,
    );

    await DmMessagesDao.instance.insertMessage(message);

    // Swarm relay removed; local persistence is the source of truth.
  }

  void broadcastTypingStatus(
    String channelOrDmTopic,
    String userId,
    bool isTyping,
  ) {
    final now = DateTime.now();
    if (isTyping) {
      _typingStatus[userId] = now;
    } else {
      _typingStatus.remove(userId);
    }

    // Typing remains local-only in this build.
  }

  bool isUserTyping(String userId) {
    final last = _typingStatus[userId];
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds < 5;
  }

  Future<List<DmMessage>> getUnreadMessages(String username) async {
    final user = await _ensureUserExists(username);
    return await DmMessagesDao.instance.getUnreadMessages(user.id);
  }

  Future<List<ChatMessage>> messagesFor(
    String serverId,
    String channelId,
  ) async {
    return await ChatDao.instance.getMessagesFor(serverId, channelId);
  }

  Future<void> sendMessage(
    String serverId,
    String channelId,
    String author,
    String text,
  ) async {
    final clean = _sanitize(text);
    if (clean.isEmpty) {
      throw ArgumentError('Cannot send empty message');
    }

    final message = ChatMessage(
      id: _uuid.v4(),
      serverId: serverId,
      channelId: channelId,
      author: author,
      text: clean,
      timestamp: DateTime.now(),
    );

    await ChatDao.instance.insertChatMessage(message);
  }

  Future<List<ChatMessage>> directMessagesBetween(
    String userA,
    String userB,
  ) async {
    final conversation = await getOrCreateConversation(userA, userB);
    final dmMessages = await DmMessagesDao.instance.getMessagesForConversation(
      conversation.id,
      limit: 500,
      offset: 0,
    );

    final userAInfo = await UsersDao.instance.getUserByName(userA);
    final userBInfo = await UsersDao.instance.getUserByName(userB);

    return dmMessages
        .map(
          (dm) => ChatMessage(
            id: dm.id,
            serverId: '',
            channelId: conversation.id,
            author: dm.senderId == userAInfo?.id ? userA : userB,
            text: dm.content,
            timestamp: dm.timestamp,
          ),
        )
        .toList();
  }

  Future<List<ChatHubEntry>> getChatHubEntries(String currentUser) async {
    final hub = <ChatHubEntry>[];

    final user = await _ensureUserExists(currentUser);
    final conversations = await conversationsFor(currentUser);

    for (final conv in conversations) {
      final peerId = conv.participant1Id == user.id
          ? conv.participant2Id
          : conv.participant1Id;
      final peerUser = await UsersDao.instance.getUserById(peerId);
      final peerName = peerUser?.username ?? 'Unknown';
      final unread = await DmMessagesDao.instance.getUnreadCountForConversation(
        conv.id,
        user.id,
      );
      final messages = await DmMessagesDao.instance.getMessagesForConversation(
        conv.id,
        limit: 1,
        offset: 0,
      );
      final latest = messages.isNotEmpty ? messages.last : null;
      hub.add(
        ChatHubEntry(
          id: conv.id,
          type: ChatHubEntryType.dm,
          title: peerName,
          subtitle: latest?.content ?? 'No messages yet',
          conversationId: conv.id,
          unread: unread,
          lastUpdated: latest?.timestamp ?? conv.createdAt,
        ),
      );
    }

    final servers = ServerService.instance.servers;
    for (final server in servers) {
      for (final channel in server.channels) {
        final messages = await ChatDao.instance.getMessagesFor(
          server.id,
          channel.id,
        );
        final latest = messages.isNotEmpty ? messages.last : null;
        hub.add(
          ChatHubEntry(
            id: '${server.id}:${channel.id}',
            type: ChatHubEntryType.serverChannel,
            title: '${server.name} / ${channel.name}',
            subtitle: latest?.text ?? 'No messages yet',
            serverId: server.id,
            channelId: channel.id,
            unread: 0,
            lastUpdated:
                latest?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
    }

    hub.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return hub;
  }

  Future<void> addReaction(String messageId, String emoji) async {
    // Reactions not persisted for DM messages in current schema, no-op for now.
    return;
  }

  Future<void> updateMessageText(String messageId, String updatedText) async {
    final dmMessage = await DmMessagesDao.instance.getMessageById(messageId);
    if (dmMessage != null) {
      await DmMessagesDao.instance.updateMessage(
        dmMessage.copyWith(content: updatedText),
      );
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await DmMessagesDao.instance.deleteMessage(messageId);
  }

  static String dmChannelId(String userA, String userB) {
    final ids = [userA.trim(), userB.trim()]..sort();
    return 'dm-${ids[0]}-${ids[1]}';
  }

  static String dmTopic(String userA, String userB) {
    final ids = [userA.trim(), userB.trim()]..sort();
    return 'dm:${ids.join('_')}';
  }

  @Deprecated('Use dmTopic instead.')
  static String dmSwarmTopic(String userA, String userB) {
    return dmTopic(userA, userB);
  }

  bool messageMentions(String userId, String text) {
    final mentionToken = '@${userId.trim()}';
    return text.split(RegExp(r'\s+')).contains(mentionToken);
  }

  String _sanitize(String text) {
    return text
        .trim()
        .replaceAll(RegExp(r"[\x00-\x1F]"), '')
        .replaceAll(RegExp(r'<[^>]*>'), '');
  }

  String _ensureString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Uint8List) {
      try {
        return utf8.decode(value, allowMalformed: true);
      } catch (e) {
        debugPrint('ChatService._ensureString decode error: $e');
        return value.toString();
      }
    }
    try {
      return value.toString();
    } catch (e) {
      debugPrint('ChatService._ensureString toString error: $e');
      return '';
    }
  }

  Future<void> _listenForPendingMessages() async {}
}
