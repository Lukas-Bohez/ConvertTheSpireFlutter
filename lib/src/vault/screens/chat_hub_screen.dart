import 'package:convert_the_spire_reborn/src/vault/models/chat_hub_entry.dart';
import 'package:convert_the_spire_reborn/src/vault/models/server.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/chat_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/dm_screen.dart';
import 'package:convert_the_spire_reborn/src/vault/services/chat_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/identity_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/server_service.dart';
import 'package:flutter/material.dart';

class ChatHubScreen extends StatefulWidget {
  const ChatHubScreen({super.key});

  @override
  State<ChatHubScreen> createState() => _ChatHubScreenState();
}

class _ChatHubScreenState extends State<ChatHubScreen> {
  final _searchController = TextEditingController();
  final _dmTargetController = TextEditingController();
  String _query = '';
  late String _currentUser;
  Future<List<ChatHubEntry>>? _entriesFuture;

  @override
  void initState() {
    super.initState();
    _currentUser = IdentityService.instance.identity?.displayName ?? 'you';
    _loadEntries();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _dmTargetController.dispose();
    super.dispose();
  }

  void _loadEntries() {
    setState(() {
      _entriesFuture = ChatService.instance.getChatHubEntries(_currentUser);
    });
  }

  Future<void> _openEntry(ChatHubEntry entry) async {
    if (entry.isDM) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DMScreen(user: _currentUser, peer: entry.title),
        ),
      );
    } else {
      final server = ServerService.instance.servers.firstWhere(
        (s) => s.id == entry.serverId,
        orElse: () =>
            ServerModel(id: entry.serverId, name: 'Unknown', channels: []),
      );
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(server: server, channelId: entry.channelId),
        ),
      );
    }
    _loadEntries();
  }

  Future<void> _startDm() async {
    final target = _dmTargetController.text.trim();
    if (target.isEmpty) return;

    await ChatService.instance.getOrCreateConversation(_currentUser, target);
    _dmTargetController.clear();
    _loadEntries();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search chats',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    setState(() => _query = value.trim().toLowerCase());
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadEntries,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dmTargetController,
                  decoration: const InputDecoration(
                    labelText: 'New DM',
                    hintText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _startDm, child: const Text('Start')),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ChatHubEntry>>(
            future: _entriesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final cs = Theme.of(context).colorScheme;
                return Center(
                  child: Container(
                    color: cs.errorContainer,
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error, color: cs.error, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            'Error loading chats:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cs.error,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: TextStyle(color: cs.error),
                          ),
                          if (snapshot.stackTrace != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                snapshot.stackTrace
                                    .toString()
                                    .split('\n')
                                    .take(6)
                                    .join('\n'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.error,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              final entries = snapshot.data ?? [];
              final filtered = _query.isEmpty
                  ? entries
                  : entries.where((entry) {
                      final combined =
                          '${entry.title} ${entry.subtitle}'.toLowerCase();
                      return combined.contains(_query);
                    }).toList();
              if (filtered.isEmpty) {
                return const Center(child: Text('No chats found.'));
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = filtered[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        entry.type == ChatHubEntryType.dm ? 'DM' : 'S',
                      ),
                    ),
                    title: Text(entry.title),
                    subtitle: Text(
                      entry.subtitle.isNotEmpty
                          ? entry.subtitle
                          : 'No messages yet',
                    ),
                    trailing: entry.unread > 0
                        ? CircleAvatar(
                            radius: 12,
                            child: Text(entry.unread.toString()),
                          )
                        : null,
                    onTap: () => _openEntry(entry),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
