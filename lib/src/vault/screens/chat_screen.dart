import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:convert_the_spire_reborn/src/vault/models/chat_message.dart';
import 'package:convert_the_spire_reborn/src/vault/models/server.dart';
import 'package:convert_the_spire_reborn/src/vault/services/chat_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/sound_service.dart';

class _ChatSendMessageIntent extends Intent {
  const _ChatSendMessageIntent();
}

class _ChatInsertNewlineIntent extends Intent {
  const _ChatInsertNewlineIntent();
}

class ChatScreen extends StatefulWidget {
  final ServerModel server;
  final String channelId;

  const ChatScreen({super.key, required this.server, required this.channelId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (animate) {
        _scrollController.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
    });
    _messages = await ChatService.instance.messagesFor(
      widget.server.id,
      widget.channelId,
    );
    setState(() {
      _loading = false;
    });
    _scrollToBottom(animate: false);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final sender = SettingsService.instance.displayName.isNotEmpty
        ? SettingsService.instance.displayName
        : 'Anonymous';

    await ChatService.instance.sendMessage(
      widget.server.id,
      widget.channelId,
      sender,
      text,
    );

    if (ChatService.instance.messageMentions('you', text)) {
      // await SoundService.instance.playMention(); // mention.mp3 asset missing
    } else {
      await SoundService.instance.playSend();
    }

    _controller.clear();
    _focusNode.requestFocus();
    await _loadMessages();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.server.channels.firstWhere(
      (c) => c.id == widget.channelId,
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.server.name} / ${channel.name}')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(child: Text('No messages yet.'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final isMe = m.author.toLowerCase() == 'you';
                      final ts = m.timestamp is DateTime
                          ? m.timestamp as DateTime
                          : DateTime.tryParse(m.timestamp.toString()) ??
                                DateTime.now();
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isMe
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(isMe ? 12 : 2),
                              bottomRight: Radius.circular(isMe ? 2 : 12),
                            ),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.15),
                              width: 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.author,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(m.text),
                              const SizedBox(height: 6),
                              Text(
                                '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Shortcuts(
                shortcuts: <LogicalKeySet, Intent>{
                  LogicalKeySet(
                    LogicalKeyboardKey.shift,
                    LogicalKeyboardKey.enter,
                  ): const _ChatInsertNewlineIntent(),
                  LogicalKeySet(LogicalKeyboardKey.enter):
                      const _ChatSendMessageIntent(),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _ChatSendMessageIntent:
                        CallbackAction<_ChatSendMessageIntent>(
                          onInvoke: (intent) async {
                            await _send();
                            return null;
                          },
                        ),
                    _ChatInsertNewlineIntent:
                        CallbackAction<_ChatInsertNewlineIntent>(
                          onInvoke: (intent) {
                            final selection = _controller.selection;
                            final text = _controller.text;
                            final newText = text.replaceRange(
                              selection.start,
                              selection.end,
                              '\n',
                            );
                            _controller.value = TextEditingValue(
                              text: newText,
                              selection: TextSelection.collapsed(
                                offset: selection.start + 1,
                              ),
                            );
                            return null;
                          },
                        ),
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          focusNode: _focusNode,
                          controller: _controller,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          onSubmitted: (_) async {
                            await _send();
                          },
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _send,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
