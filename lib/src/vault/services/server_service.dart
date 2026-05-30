import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:convert_the_spire_reborn/src/vault/db/server_dao.dart';
import 'package:convert_the_spire_reborn/src/vault/models/server.dart';
import '../../utils/safe_json.dart';

class ServerService {
  ServerService._();
  static final ServerService instance = ServerService._();

  final _uuid = const Uuid();
  final List<ServerModel> _servers = [];

  List<ServerModel> get servers => List.unmodifiable(_servers);

  Future<void> init() async {
    _servers
      ..clear()
      ..addAll(await ServerDao.instance.getAllServers());
  }

  ServerModel createServer({required String name, String description = ''}) {
    final server = ServerModel(
      id: _uuid.v4(),
      name: name,
      description: description,
      channels: [
        ChannelModel(id: _uuid.v4(), name: 'general', isVoice: false),
        ChannelModel(id: _uuid.v4(), name: 'voice-1', isVoice: true),
      ],
    );
    _servers.add(server);
    ServerDao.instance.insertServer(server);
    return server;
  }

  Future<bool> joinServer(String inviteCode) async {
    // allow direct server id or JSON invite token.
    String serverId = inviteCode;

    if (inviteCode.startsWith('{') || inviteCode.startsWith('ey')) {
      final decoded = _decodeInvite(inviteCode);
      if (decoded == null) return false;
      serverId = decoded.id;
    }

    final existing = _servers.firstWhere(
      (s) => s.id == serverId,
      orElse: () => ServerModel(id: '', name: '', channels: []),
    );

    if (existing.id.isNotEmpty) {
      return true;
    }

    final dbServer = await ServerDao.instance.getServerById(serverId);
    if (dbServer != null) {
      _servers.add(dbServer);
      return true;
    }

    final decoded = _decodeInvite(inviteCode);
    if (decoded != null) {
      _servers.add(decoded);
      await ServerDao.instance.insertServer(decoded);
      return true;
    }

    return false;
  }

  String reformatInvite(ServerModel server) => jsonEncode({
        'id': server.id,
        'name': server.name,
        'description': server.description,
      });

  String encodeInvite(ServerModel server) {
    return base64Url.encode(utf8.encode(reformatInvite(server)));
  }

  ServerModel? _decodeInvite(String invite) {
    try {
      String jsonString = invite;
      if (!invite.startsWith('{')) {
        jsonString = utf8.decode(base64Url.decode(invite));
      }
      final data = safeJsonDecode<Map<String, dynamic>>(jsonString);
      if (data == null) return null;
      final id = data['id'] as String?;
      if (id == null || id.isEmpty) return null;
      return ServerModel(
        id: id,
        name: data['name'] as String? ?? 'Invitation',
        description: data['description'] as String? ?? '',
        channels: [
          ChannelModel(id: _uuid.v4(), name: 'general', isVoice: false),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> updateServer(ServerModel server) async {
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index == -1) {
      _servers.add(server);
    } else {
      _servers[index] = server;
    }
    await ServerDao.instance.updateServer(server);
  }

  Future<ServerModel> addChannel(
    String serverId,
    String name, {
    bool isVoice = false,
  }) async {
    final serverIndex = _servers.indexWhere((s) => s.id == serverId);
    if (serverIndex == -1) throw StateError('Server not found');

    final server = _servers[serverIndex];
    final newChannel = ChannelModel(
      id: _uuid.v4(),
      name: name,
      isVoice: isVoice,
    );
    final updatedServer = server.copyWith(
      channels: [...server.channels, newChannel],
    );

    _servers[serverIndex] = updatedServer;
    await ServerDao.instance.updateServer(updatedServer);
    return updatedServer;
  }

  Future<void> removeChannel(String serverId, String channelId) async {
    final serverIndex = _servers.indexWhere((s) => s.id == serverId);
    if (serverIndex == -1) throw StateError('Server not found');

    final server = _servers[serverIndex];
    final updatedServer = server.copyWith(
      channels: server.channels.where((c) => c.id != channelId).toList(),
    );

    _servers[serverIndex] = updatedServer;
    await ServerDao.instance.updateServer(updatedServer);
  }

  Future<void> renameServer(String serverId, String name) async {
    final serverIndex = _servers.indexWhere((s) => s.id == serverId);
    if (serverIndex == -1) throw StateError('Server not found');

    final server = _servers[serverIndex];
    final updatedServer = server.copyWith(name: name);

    _servers[serverIndex] = updatedServer;
    await ServerDao.instance.updateServer(updatedServer);
  }

  Future<void> removeServer(String id) async {
    _servers.removeWhere((s) => s.id == id);
    await ServerDao.instance.deleteServer(id);
  }

  String generateInvite(ServerModel server) => server.id;

  ServerModel? decodeInvite(String invite) => _decodeInvite(invite);
}
