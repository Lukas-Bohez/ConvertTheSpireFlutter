// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:convert_the_spire_reborn/src/vault/models/chat_message.dart';
import 'package:convert_the_spire_reborn/src/vault/services/chat_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/sound_service.dart';

class DMScreen extends StatefulWidget {
  final String user;
  final String peer;

  const DMScreen({super.key, required this.user, required this.peer});

  @override
  State<DMScreen> createState() => _DMScreenState();
}

class _DMScreenState extends State<DMScreen> {
  final _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  ChatMessage? _replyTarget;

  @override
  void initState() {
    super.initState();
    _typingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && ChatService.instance.isUserTyping(widget.peer)) {
        setState(() {});
      }
    });
    _loadMessages();
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
    });
    _messages = await ChatService.instance.directMessagesBetween(
      widget.user,
      widget.peer,
    );
    setState(() {
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final topic = ChatService.dmTopic(widget.user, widget.peer);
    ChatService.instance.broadcastTypingStatus(topic, widget.user, false);

    if (text.isEmpty) return;
    await ChatService.instance.sendDirectMessage(
      widget.user,
      widget.peer,
      text,
      replyToMessageId: _replyTarget?.id,
    );
    _replyTarget = null;

    if (ChatService.instance.messageMentions(widget.user, text) ||
        ChatService.instance.messageMentions(widget.peer, text)) {
      // await SoundService.instance.playMention(); // mention.mp3 asset missing
    } else {
      await SoundService.instance.playSend();
    }

    _controller.clear();
    await _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // overflow-fix: long usernames can overflow AppBar title on narrow devices.
        title: Text(
          'DM: ${widget.user} ↔ ${widget.peer}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? const Center(
                    child: Text('No DMs yet. Start the conversation.'),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final mentionsCurrent = ChatService.instance
                          .messageMentions(widget.user, m.text);
                      final isMe = m.author == widget.user;
                      return ListTile(
                        tileColor: isMe
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        title: Text(
                          '${m.author} • ${m.timestamp.hour}:${m.timestamp.minute.toString().padLeft(2, '0')}',
                          // overflow-fix: bound metadata title in list tiles.
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              m.text,
                              style: TextStyle(
                                color: mentionsCurrent
                                    ? Theme.of(context).colorScheme.secondary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Wrap(
                              spacing: 4,
                              children: m.reactions.entries
                                  .map(
                                    (entry) => Chip(
                                      label: Text(
                                        '${entry.key} ${entry.value}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                        onLongPress: () async {
                          final parentContext = context;
                          final action = await showModalBottomSheet<String>(
                            context: parentContext,
                            builder: (ctx) {
                              return Wrap(
                                spacing: 4,
                                children: [
                                  ListTile(
                                    leading: const Icon(Icons.emoji_emotions),
                                    title: const Text('React'),
                                    onTap: () => Navigator.of(ctx).pop('react'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.edit),
                                    title: const Text('Edit'),
                                    onTap: () => Navigator.of(ctx).pop('edit'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.repeat),
                                    title: const Text('Reply'),
                                    onTap: () => Navigator.of(ctx).pop('reply'),
                                  ),
                                  ListTile(
                                    leading: const Icon(Icons.delete),
                                    title: const Text('Delete'),
                                    onTap: () =>
                                        Navigator.of(ctx).pop('delete'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (action == 'react') {
                            final emoji = await showModalBottomSheet<String>(
                              context: parentContext,
                              builder: (ctx) {
                                return Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: ['👍', '❤️', '😂', '😮', '😢', '🔥']
                                      .map(
                                        (e) => ChoiceChip(
                                          label: Text(e),
                                          selected: false,
                                          onSelected: (_) {
                                            Navigator.of(ctx).pop(e);
                                          },
                                        ),
                                      )
                                      .toList(),
                                );
                              },
                            );
                            if (emoji != null) {
                              await ChatService.instance.addReaction(
                                m.id,
                                emoji,
                              );
                              if (!mounted) return;
                              setState(() {});
                            }
                          } else if (action == 'reply') {
                            setState(() {
                              _replyTarget = m;
                            });
                          } else if (action == 'edit') {
                            final editController = TextEditingController(
                              text: m.text,
                            );
                            final edited = await showDialog<String>(
                              context: parentContext,
                              builder: (ctx) {
                                return AlertDialog(
                                  title: const Text('Edit message'),
                                  // overflow-fix: allow dialog content to scroll when keyboard reduces height.
                                  content: SingleChildScrollView(
                                    child: TextField(
                                      controller: editController,
                                      autofocus: true,
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(
                                        ctx,
                                      ).pop(editController.text.trim()),
                                      child: const Text('Save'),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (edited != null &&
                                edited.isNotEmpty &&
                                edited != m.text) {
                              await ChatService.instance.updateMessageText(
                                m.id,
                                edited,
                              );
                              if (!mounted) return;
                              setState(() {});
                            }
                          } else if (action == 'delete') {
                            final confirm = await showDialog<bool>(
                              context: parentContext,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete message?'),
                                // overflow-fix: keep dialog body scroll-safe on small screens.
                                content: const SingleChildScrollView(
                                  child: Text('This cannot be undone.'),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Theme.of(ctx).colorScheme.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await ChatService.instance.deleteMessage(m.id);
                              if (!mounted) return;
                              setState(() {});
                            }
                          }
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_replyTarget != null)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _replyTarget = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: Text(
                              'Replying to ${_replyTarget!.author} • tap to cancel',
                            ),
                          ),
                        ),
                      TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) async {
                          await _send();
                        },
                        decoration: InputDecoration(
                          hintText: _replyTarget != null
                              ? 'Replying to ${_replyTarget!.author}'
                              : 'Type a direct message',
                        ),
                        onChanged: (value) {
                          final topic = ChatService.dmTopic(
                            widget.user,
                            widget.peer,
                          );
                          ChatService.instance.broadcastTypingStatus(
                            topic,
                            widget.user,
                            value.isNotEmpty,
                          );
                          if (value.isNotEmpty) {
                            _typingTimer?.cancel();
                            _typingTimer = Timer(
                              const Duration(seconds: 5),
                              () {
                                ChatService.instance.broadcastTypingStatus(
                                  topic,
                                  widget.user,
                                  false,
                                );
                                if (mounted) setState(() {});
                              },
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ),
          if (ChatService.instance.isUserTyping(widget.peer))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.more_horiz, size: 16),
                  const SizedBox(width: 4),
                  Text('${widget.peer} is typing...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
