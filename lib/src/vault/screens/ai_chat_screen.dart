import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:convert_the_spire_reborn/src/vault/constants.dart';
import 'package:convert_the_spire_reborn/src/vault/services/ai_copilot_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _baseUrlController = TextEditingController(
    text: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? kAndroidLocalOllamaUrl
        : 'http://localhost:11434',
  );
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  late final AiCopilotService _aiService;
  List<_UiMessage> _messages = <_UiMessage>[];
  List<String> _models = <String>[];
  bool _checking = false;
  bool _sending = false;
  bool _pulling = false;
  bool _ollamaInstalled = false;
  String _status = 'Not connected';
  String _activeModel = kDefaultAiModel;
  Timer? _streamPaintTimer;
  DateTime _lastStreamPaint = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _streamPaintInterval = Duration(milliseconds: 80);
  String _pendingAssistantText = '';

  @override
  void initState() {
    super.initState();
    _aiService = AiCopilotService(baseUrl: _baseUrlController.text.trim());
    _initialize();
  }

  @override
  void dispose() {
    _streamPaintTimer?.cancel();
    _baseUrlController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _applyAssistantChunk(String fullText) {
    final updated = List<_UiMessage>.from(_messages);
    final idx = updated.lastIndexWhere((m) => m.role == 'assistant');
    if (idx >= 0) {
      updated[idx] = updated[idx].copyWith(content: fullText);
      _messages = updated;
    }
  }

  void _queueAssistantChunk(String fullText, {bool force = false}) {
    _pendingAssistantText = fullText;
    final now = DateTime.now();
    final elapsed = now.difference(_lastStreamPaint);

    if (force || elapsed >= _streamPaintInterval) {
      _streamPaintTimer?.cancel();
      _lastStreamPaint = now;
      setState(() {
        _applyAssistantChunk(_pendingAssistantText);
      });
      return;
    }

    if (_streamPaintTimer?.isActive ?? false) {
      return;
    }

    _streamPaintTimer = Timer(_streamPaintInterval - elapsed, () {
      if (!mounted) return;
      _lastStreamPaint = DateTime.now();
      setState(() {
        _applyAssistantChunk(_pendingAssistantText);
      });
    });
  }

  Future<void> _initialize() async {
    _baseUrlController.text = SettingsService.instance.aiOllamaUrl;
    _aiService.setBaseUrl(_baseUrlController.text.trim());
    _activeModel = SettingsService.instance.aiDefaultModel;
    await _checkLocalOllama();
    await _refreshModels();
  }

  Future<void> _checkLocalOllama() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return;
    }
    try {
      final result = await Process.run('ollama', const ['--version']);
      if (!mounted) return;
      setState(() {
        _ollamaInstalled = result.exitCode == 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ollamaInstalled = false;
      });
    }
  }

  Future<void> _connect() async {
    final trimmed = _baseUrlController.text.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _checking = true;
      _status = 'Connecting to $trimmed ...';
    });

    _aiService.setBaseUrl(trimmed);
    final ok = await _aiService.checkVersion();
    if (!mounted) return;

    setState(() {
      _checking = false;
      _status = ok
          ? 'Connected to Ollama at $trimmed'
          : 'Cannot reach Ollama at $trimmed';
    });

    if (ok) {
      await _refreshModels();
    }
  }

  Future<void> _refreshModels() async {
    setState(() {
      _checking = true;
    });

    try {
      final models = await _aiService.fetchModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        if (_models.isEmpty) {
          _status =
              'Connected. No local models found, fallback set to $kDefaultAiModel';
        } else if (_models.contains(_activeModel)) {
          _status = 'Connected. Selected model: $_activeModel';
        } else if (_models.contains(kDefaultAiModel)) {
          _status =
              'Connected. Selected model not installed; recommended model is available.';
        } else {
          _status =
              'Connected. Selected model not installed; choose one from the list.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _models = <String>[];
        _activeModel = kDefaultAiModel;
      });
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  Future<void> _selectModel(String model) async {
    setState(() {
      _activeModel = model;
      _status = 'Selected model: $model';
    });
    await SettingsService.instance.setAiDefaultModel(model);
  }

  Future<void> _downloadRecommendedModel() async {
    if (_pulling) return;

    setState(() {
      _pulling = true;
      _status = 'Downloading recommended model $kDefaultAiModel ...';
    });

    try {
      await for (final event in _aiService.pullModelStream(kDefaultAiModel)) {
        final status = (event['status'] ?? '').toString();
        final total = (event['total'] as num?)?.toDouble() ?? 0;
        final completed = (event['completed'] as num?)?.toDouble() ?? 0;
        final progress = total > 0
            ? (completed / total * 100).clamp(0, 100)
            : 0;

        if (!mounted) return;
        setState(() {
          if (progress > 0) {
            _status =
                '$status (${progress.toStringAsFixed(1)}%) for $kDefaultAiModel';
          } else {
            _status = status.isEmpty
                ? 'Downloading $kDefaultAiModel ...'
                : status;
          }
        });
      }
      await _refreshModels();
      await _selectModel(kDefaultAiModel);
      if (!mounted) return;
      setState(() {
        _status = 'Recommended model $kDefaultAiModel is ready.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Model download failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _pulling = false;
        });
      }
    }
  }

  Future<void> _startOllamaServer() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return;
    }
    try {
      await Process.start(
        'ollama',
        const ['serve'],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      if (!mounted) return;
      setState(() {
        _status = 'Started local Ollama server.';
      });
      await Future<void>.delayed(const Duration(seconds: 1));
      await _connect();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Failed to start Ollama server: $e';
      });
    }
  }

  Future<void> _installOllama() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return;
    }

    setState(() {
      _status = 'Installing Ollama...';
    });

    try {
      if (Platform.isWindows) {
        final result = await Process.run('winget', const [
          'install',
          '--id',
          'Ollama.Ollama',
          '-e',
          '--silent',
          '--accept-package-agreements',
          '--accept-source-agreements',
        ], runInShell: true);
        if (result.exitCode != 0) {
          await launchUrl(Uri.parse('https://ollama.com/download/windows'));
        }
      } else if (Platform.isMacOS) {
        final result = await Process.run('brew', const ['install', 'ollama']);
        if (result.exitCode != 0) {
          await launchUrl(Uri.parse('https://ollama.com/download/mac'));
        }
      } else {
        await launchUrl(Uri.parse('https://ollama.com/download/linux'));
      }
    } catch (_) {
      final suffix = Platform.isWindows
          ? 'windows'
          : (Platform.isMacOS ? 'mac' : 'linux');
      await launchUrl(Uri.parse('https://ollama.com/download/$suffix'));
    }

    await _checkLocalOllama();
    if (!mounted) return;
    setState(() {
      _status = _ollamaInstalled
          ? 'Ollama installed locally.'
          : 'Installer launched. Complete install then reconnect.';
    });
  }

  Future<void> _sendChat() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _sending) return;

    final model = _activeModel.trim().isEmpty ? kDefaultAiModel : _activeModel;
    _chatController.clear();

    setState(() {
      _sending = true;
      _pendingAssistantText = '';
      _messages = <_UiMessage>[
        ..._messages,
        _UiMessage(role: 'user', content: text),
        _UiMessage(role: 'assistant', content: ''),
      ];
    });

    try {
      final stream = await _aiService.chatStream(
        model: model,
        messages: [
          {'role': 'user', 'content': text},
        ],
      );

      await for (final chunk in stream) {
        if (!mounted) return;
        final updated = List<_UiMessage>.from(_messages);
        final idx = updated.lastIndexWhere((m) => m.role == 'assistant');
        if (idx >= 0) {
          final currentText = _pendingAssistantText.isNotEmpty
              ? _pendingAssistantText
              : updated[idx].content;
          final nextText = currentText + chunk;
          _queueAssistantChunk(nextText);
        }
        _scrollToBottom();
      }

      if (mounted) {
        _queueAssistantChunk(_pendingAssistantText, force: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = <_UiMessage>[
          ..._messages,
          _UiMessage(role: 'assistant', content: 'Error: $e'),
        ];
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local AI Chat (Ollama)'),
        actions: [
          IconButton(
            onPressed: _checking ? null : _refreshModels,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh model status',
          ),
        ],
      ),
      body: isDesktop
          ? Row(
              children: [
                SizedBox(
                  width: 360,
                  child: _buildControlPanel(context),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _buildChatPanel(context)),
              ],
            )
          : Column(
              children: [
                SizedBox(
                  height: (size.height * 0.42).clamp(280.0, 420.0),
                  child: _buildControlPanel(context),
                ),
                const Divider(height: 1),
                Expanded(child: _buildChatPanel(context)),
              ],
            ),
    );
  }

  Widget _buildControlPanel(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        TextField(
          controller: _baseUrlController,
          decoration: const InputDecoration(
            labelText: 'Ollama URL',
            hintText: 'http://localhost:11434',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _checking ? null : _connect,
                icon: const Icon(Icons.link),
                label: const Text('Connect'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _startOllamaServer,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Local'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _installOllama,
                icon: const Icon(Icons.download),
                label: const Text('Install Ollama'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _ollamaInstalled ? 'Ollama CLI detected' : 'Ollama CLI not detected',
          style: TextStyle(
            color: _ollamaInstalled
                ? Theme.of(context).colorScheme.tertiary
                : Theme.of(context).colorScheme.secondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(_status, style: Theme.of(context).textTheme.bodySmall),
        const Divider(height: 24),
        const Text(
          'Model routing',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recommended model: $kDefaultAiModel'),
              const SizedBox(height: 6),
              Text('Active model: $_activeModel'),
              const SizedBox(height: 6),
              Text(
                _models.isEmpty
                    ? 'No local model list returned. The app will still try the recommended model.'
                    : 'Detected ${_models.length} installed model(s).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_models.isNotEmpty) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _models.contains(_activeModel)
                      ? _activeModel
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Select model to use',
                    border: OutlineInputBorder(),
                  ),
                  items: _models
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m,
                          child: Text(m),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    _selectModel(value);
                  },
                ),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _pulling ? null : _downloadRecommendedModel,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(
                  _pulling
                      ? 'Downloading recommended model...'
                      : 'Download Recommended Model',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatPanel(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const Center(child: Text('Ask your local model anything.'))
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final isUser = message.role == 'user';
                    return Align(
                      alignment: isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 680),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isUser
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          message.content.isEmpty && !isUser
                              ? '...'
                              : message.content,
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_sending) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  minLines: 1,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Type a message to your local AI...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendChat(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _sending ? null : _sendChat,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UiMessage {
  final String role;
  final String content;

  const _UiMessage({required this.role, required this.content});

  _UiMessage copyWith({String? role, String? content}) {
    return _UiMessage(
      role: role ?? this.role,
      content: content ?? this.content,
    );
  }
}
