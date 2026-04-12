import 'package:uuid/uuid.dart';
import 'package:convert_the_spire_reborn/src/vault/db/messages_dao.dart';
import 'package:convert_the_spire_reborn/src/vault/models/message.dart';

class MessageService {
  MessageService._();

  static final MessageService instance = MessageService._();

  final _uuid = const Uuid();

  Future<List<MessageModel>> getMessages() =>
      MessagesDao.instance.getAllMessages();

  Future<void> sendLocalMessage({
    required String sender,
    required String recipient,
    required String body,
    String protocol = 'local',
  }) async {
    final message = MessageModel(
      id: _uuid.v4(),
      sender: sender,
      recipient: recipient,
      body: body,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isSent: true,
      protocol: protocol,
    );

    await MessagesDao.instance.insertMessage(message);
  }

  Future<void> saveDraftMessage({
    required String sender,
    required String recipient,
    required String body,
  }) async {
    final message = MessageModel(
      id: _uuid.v4(),
      sender: sender,
      recipient: recipient,
      body: body,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isSent: false,
      protocol: 'draft',
    );

    await MessagesDao.instance.insertMessage(message);
  }

  Future<void> deleteMessage(String id) async =>
      MessagesDao.instance.deleteMessage(id);
}
