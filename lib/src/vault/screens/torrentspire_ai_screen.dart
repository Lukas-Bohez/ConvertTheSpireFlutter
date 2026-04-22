import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:convert_the_spire_reborn/src/config/full_mode_access.dart';
import 'package:convert_the_spire_reborn/src/vault/constants.dart';
import 'package:convert_the_spire_reborn/src/vault/models/ai_chat_entry.dart';
import 'package:convert_the_spire_reborn/src/vault/models/torrent.dart';
import 'package:convert_the_spire_reborn/src/vault/services/ai_copilot_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/ai_triggers.dart';
import 'package:convert_the_spire_reborn/src/vault/services/intent_parser.dart';
import 'package:convert_the_spire_reborn/src/vault/services/search_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/settings_service.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_context.dart';
import 'package:convert_the_spire_reborn/src/vault/services/torrent_service.dart';
import 'package:convert_the_spire_reborn/src/vault/screens/create_torrent_screen.dart';

class TorrentSpireAiScreen extends StatefulWidget {
  const TorrentSpireAiScreen({super.key});

  @override
  State<TorrentSpireAiScreen> createState() => _TorrentSpireAiScreenState();
}

class _TorrentSpireAiScreenState extends State<TorrentSpireAiScreen>
  with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _magnetController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  final AiCopilotService _aiService = AiCopilotService();
  final TorrentContextService _contextService = TorrentContextService();
  final AiTriggers _triggers = AiTriggers();
  final IntentParser _intentParser = IntentParser();

  final List<AiChatEntry> _messages = <AiChatEntry>[];
  List<SearchResult> _results = <SearchResult>[];
  List<TorrentModel> _torrents = <TorrentModel>[];
  List<TorrentViewState> _torrentStates = <TorrentViewState>[];

  StreamSubscription<List<SearchResult>>? _searchSubscription;
  StreamSubscription<List<TorrentViewState>>? _torrentStatesSubscription;

  SearchResult? _selected;
  String _category = 'All';
  String _activeModel = kDefaultAiModel;
  String _cachedAiUrl = '';
  String _cachedAiModel = '';
  String _infoCardText = 'Select a torrent to generate AI analysis.';
  String _trustSignal = 'Neutral';
  bool _aiReady = false;
  bool _infoCardLoading = false;
  bool _resolvingMagnet = false;
  bool _focusMode = false;
  bool _chatMode = false;
  bool _isSending = false;
  double _splitRatio = 0.58;
  final Set<String> _triggeredEventKeys = <String>{};
  final List<AiTriggerEvent> _queuedAutoEvents = <AiTriggerEvent>[];
  Timer? _streamPaintTimer;
  DateTime _lastStreamPaint = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _streamPaintInterval = Duration(milliseconds: 80);
  static const int _playModeTorrentCap = 50;
  String _pendingStreamText = '';

  bool get _isLimitedPlayMode => FullModeAccess.instance.isLimitedPlayMode;

  bool _reachedPlayModeTorrentCap() {
    return _isLimitedPlayMode && _torrentStates.length >= _playModeTorrentCap;
  }

  void _showPlayModeCapMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Play mode is limited to 50 torrents. Unlock full mode to continue.'),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeModel = SettingsService.instance.aiDefaultModel;
    _cachedAiModel = _activeModel;
    final url = SettingsService.instance.aiOllamaUrl;
    _aiService.setBaseUrl(url);
    _cachedAiUrl = url;
    _contextService.addListener(_noop);
    _searchSubscription = SearchService.instance.resultsStream.listen((items) {
      setState(() {
        _results = items;
      });
      if (items.isEmpty && _searchController.text.trim().isNotEmpty) {
        _triggerAutoEvent(
          _triggers.onZeroResults(_searchController.text.trim()),
        );
      }
    });
    _torrentStatesSubscription = TorrentService.instance.torrentStatesStream
        .listen((states) {
          _torrentStates = states;
          _torrents = states.map((s) => s.model).toList();
          _contextService.updateTorrents(_torrents);
          if (mounted) {
            setState(() {});
          }
        });
    unawaited(TorrentService.instance.refreshTorrentStates());
    _checkAiReadiness();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDownloadFolderOnInit();
    });
  }

  Future<void> _checkDownloadFolderOnInit() async {
    final folder = SettingsService.instance.downloadDestination.trim();
    if (folder.isEmpty) {
      if (!mounted) return;
      _showSetDownloadFolderDialog();
    }
  }

  Future<bool> _validateDownloadFolder() async {
    final folder = SettingsService.instance.downloadDestination.trim();
    if (folder.isEmpty) {
      if (mounted) {
        _showSetDownloadFolderDialog();
      }
      return false;
    }

    // Check if folder exists and is accessible
    try {
      final dir = Directory(folder);
      if (!dir.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Download folder "$folder" no longer exists.'),
              action: SnackBarAction(
                label: 'Change',
                onPressed: _showSetDownloadFolderDialog,
              ),
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return false;
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot access download folder: $e'),
            action: SnackBarAction(
              label: 'Change',
              onPressed: _showSetDownloadFolderDialog,
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return false;
    }
  }

  void _showSetDownloadFolderDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Download Folder'),
        // overflow-fix: keep long guidance text scroll-safe on compact devices.
        content: const SingleChildScrollView(
          child: Text(
            'You must set a download folder before downloading torrents. '
            'This prevents downloads from being stored in inaccessible app storage and causing file corruption. '
            'Please navigate to Settings and select a folder on external storage.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _magnetController.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    _searchSubscription?.cancel();
    _torrentStatesSubscription?.cancel();
    _streamPaintTimer?.cancel();
    // _settingsSyncTimer?.cancel(); // TODO: re-enable
    _contextService.removeListener(_noop);
    _contextService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(TorrentService.instance.refreshTorrentStates());
      return;
    }
  }

  void _applyStreamingAssistantText(String fullText) {
    final index = _messages.lastIndexWhere(
      (m) => m.isStreaming && m.role == 'assistant',
    );
    if (index >= 0) {
      _messages[index] = _messages[index].copyWith(content: fullText);
    }
  }

  void _queueStreamingAssistantText(String fullText, {bool force = false}) {
    _pendingStreamText = fullText;
    final now = DateTime.now();
    final elapsed = now.difference(_lastStreamPaint);

    if (force || elapsed >= _streamPaintInterval) {
      _streamPaintTimer?.cancel();
      _lastStreamPaint = now;
      setState(() {
        _applyStreamingAssistantText(_pendingStreamText);
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
        _applyStreamingAssistantText(_pendingStreamText);
      });
    });
  }

  void _noop() {}

  Future<void> _refreshTorrents() async {
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _performSearch(String query) async {
    final value = query.trim();
    if (value.isEmpty) return;

    if (value.toLowerCase().startsWith('magnet:?xt=')) {
      if (_reachedPlayModeTorrentCap()) {
        _showPlayModeCapMessage();
        return;
      }
      setState(() {
        _resolvingMagnet = true;
      });
      try {
        final outcome = await TorrentService.instance
            .addTorrentFromMagnetLink(value)
            .timeout(const Duration(seconds: 30));
        if (outcome == MagnetAddOutcome.pendingMetadata && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Couldn't fetch torrent info yet - no peers responded. Added to queue and will retry metadata automatically.",
              ),
            ),
          );
        }
        _magnetController.clear();
      } on TimeoutException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Resolving metadata timed out after 30 seconds. Please retry.',
            ),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _resolvingMagnet = false;
          });
        }
      }
      return;
    }

    _contextService.updateQuery(value);
    await SearchService.instance.broadcastSearch(value);

    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_results.isEmpty) {
        _triggerAutoEvent(_triggers.onZeroResults(value));
      }
    });
  }

  Future<void> _addMagnet() async {
    if (!await _validateDownloadFolder()) return;
    final text = _magnetController.text.trim();
    if (text.isEmpty) return;
    if (_reachedPlayModeTorrentCap()) {
      _showPlayModeCapMessage();
      return;
    }
    final outcome = await TorrentService.instance.addTorrentFromMagnetLink(text);
    if (outcome == MagnetAddOutcome.pendingMetadata && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't fetch torrent info yet - no peers responded. Added to queue and will retry metadata automatically.",
          ),
        ),
      );
    }
    _magnetController.clear();
    await _refreshTorrents();
  }

  Future<void> _startDownload(SearchResult result) async {
    if (!await _validateDownloadFolder()) return;
    if (result.magnetLink.isEmpty) return;
    if (_reachedPlayModeTorrentCap()) {
      _showPlayModeCapMessage();
      return;
    }
    final outcome = await TorrentService.instance.addTorrentFromMagnetLink(
      result.magnetLink,
    );
    if (outcome == MagnetAddOutcome.pendingMetadata && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't fetch torrent info yet - no peers responded. Added to queue and will retry metadata automatically.",
          ),
        ),
      );
    }
    await _refreshTorrents();
    _triggerAutoEvent(
      _triggers.onDownloadStarted(
        name: result.name,
        size: _formatSize(result.size ?? 0),
      ),
    );
  }

  Future<void> _selectResult(SearchResult result) async {
    setState(() {
      _selected = result;
    });
    _contextService.updateSelected(result);
    _triggerAutoEvent(_triggers.onResultSelected(result));
    // Ensure AI is ready before generating info card
    await _syncAiSettings();
    await _generateInfoCard(result);
  }

  Future<void> _generateInfoCard(SearchResult result) async {
    if (!SettingsService.instance.enableAiCopilot) {
      if (!mounted) return;
      setState(() {
        _infoCardLoading = false;
        _trustSignal = 'Neutral';
        _infoCardText =
            'AI Copilot is disabled in Settings. Enable it to get analysis.';
      });
      return;
    }

    final runtime = _torrentStates
      .where((s) => s.id == result.torrentId)
      .cast<TorrentViewState?>()
      .firstWhere((s) => s != null, orElse: () => null);
    final seeders = (runtime?.seeders ?? result.seeders) ?? 0;
    final leechers = (runtime?.leechers ?? result.leechers) ?? 0;
    final peers = runtime?.peers;
    final uploaded = runtime?.uploaded;
    final swarmParts = <String>[];
    if (seeders > 0) swarmParts.add('seeders=$seeders');
    if (leechers > 0) swarmParts.add('leechers=$leechers');
    if (peers != null && peers > 0) swarmParts.add('connectedPeers=$peers');
    if (uploaded != null && uploaded > 0) {
      swarmParts.add('uploadedBytes=$uploaded');
    }
    final swarmSummary = swarmParts.isEmpty ? 'no positive swarm stats yet' : swarmParts.join(', ');
    final ageText = (result.ageYears ?? 0) > 0 ? 'ageYears=${result.ageYears}' : 'ageYears=unknown';

    final trust = _computeTrustSignal(
      result,
      runtimeSeeders: runtime?.seeders,
      runtimeLeechers: runtime?.leechers,
    );
    setState(() {
      _infoCardLoading = true;
      _trustSignal = trust;
      _infoCardText = 'Analyzing torrent metadata...';
    });

    final liveContext = _contextService.getContext();
    final prompt =
      'Give a concise 2-3 sentence description for this torrent candidate: '
      'title=${result.name}, size=${result.size ?? 0} bytes, category=$_category, '
      '$ageText, '
      'source=${result.source.isEmpty ? result.responderId : result.source}. '
      'Include likely file structure and notable quality hints. '
      'Do not call it dangerous or suspicious unless there is direct evidence. '
      'Treat zero or missing seeders, leechers, or age as unknown signal, not a warning. '
      'If evidence is weak, say that confidence is limited instead of raising a red flag. '
      'Current positive swarm stats: $swarmSummary. '
      'Use this live app context for accuracy:\n$liveContext';

    if (!mounted) return;
    
    if (!_aiReady) {
      setState(() {
        _infoCardLoading = false;
        _trustSignal = 'Neutral';
        _infoCardText = 'AI not connected. Check Settings > AI Settings and verify Ollama is running.';
      });
      return;
    }

    // Validate that the model exists
    final modelExists = await _aiService.modelExists(_activeModel);
    if (!modelExists) {
      if (!mounted) return;
      setState(() {
        _infoCardLoading = false;
        _trustSignal = 'Neutral';
        _infoCardText = 'Model "$_activeModel" not found. Download it in Settings > Local AI Chat.';
      });
      return;
    }

    try {
      final stream = await _aiService.chatChunkStream(
        model: _activeModel,
        messages: [
          {
            'role': 'system',
            'content':
                'You are a torrent analysis copilot. Be concise and practical.',
          },
          {'role': 'user', 'content': prompt},
        ],
      );
      final buffer = StringBuffer();
      await for (final chunk in stream) {
        buffer.write(chunk.content);
        if (chunk.done) break;
      }
      if (!mounted) return;
      setState(() {
        _infoCardLoading = false;
        _infoCardText = buffer.toString().trim().isEmpty
            ? 'No extra details available yet.'
            : buffer.toString().trim();
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('AI analysis failed: $e');
      setState(() {
        _infoCardLoading = false;
        _trustSignal = 'Neutral';
        _infoCardText = 'AI analysis failed: $e';
      });
    }
  }

  String _computeTrustSignal(
    SearchResult result, {
    int? runtimeSeeders,
    int? runtimeLeechers,
  }) {
    final size = result.size;
    final seeders = runtimeSeeders ?? result.seeders;
    final leechers = runtimeLeechers ?? result.leechers;
    final age = result.ageYears;

    if ((seeders == null || seeders <= 0) &&
        (leechers == null || leechers <= 0) &&
        (age == null || age <= 0)) {
      return 'Neutral';
    }

    var score = 0;

    if (seeders != null && seeders > 0) {
      if (seeders >= 200) {
        score += 3;
      } else if (seeders >= 80) {
        score += 2;
      } else if (seeders >= 20) {
        score += 1;
      } else if (seeders <= 2) {
        score -= 2;
      } else if (seeders <= 8) {
        score -= 1;
      }
    }

    if (seeders != null && seeders > 0 && leechers != null && leechers > 0) {
      if (seeders > leechers * 2) {
        score += 2;
      } else if (seeders < leechers) {
        score -= 1;
      }
    }

    if (age != null && age > 0) {
      if (age <= 1) {
        score += 1;
      } else if (age >= 8) {
        score -= 1;
      } else if (age >= 5) {
        score -= 1;
      }
    }

    if (_category == 'Movies' && size != null) {
      if (size < 350 * 1024 * 1024) {
        score -= 2;
      } else if (size > 1500 * 1024 * 1024) {
        score += 1;
      }
    }

    if (score >= 3) return 'Green';
    if (score <= -4) return 'Red';
    if (score <= -1) return 'Yellow';
    return 'Neutral';
  }

  Future<void> _triggerAutoEvent(AiTriggerEvent event) async {
    if (!SettingsService.instance.enableAiCopilot ||
        !SettingsService.instance.enableSmartSuggestions) {
      return;
    }
    if (_triggeredEventKeys.contains(event.key)) return;
    _triggeredEventKeys.add(event.key);
    if (_isSending) {
      _queuedAutoEvents.add(event);
      return;
    }
    await _sendToAi(event.prompt, auto: true, visibleUserMessage: false);
  }

  Future<void> _onUserSend() async {
    if (!SettingsService.instance.enableAiCopilot) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI Copilot is disabled in Settings.'),
        ),
      );
      return;
    }

    final text = _chatController.text.trim();
    if (text.isEmpty || _isSending) return;
    _chatController.clear();

    final parsed = _intentParser.parse(text);
    var shouldExecuteCommand = false;

    if (_intentParser.passesKeywordGate(text) &&
        parsed.type != TorrentIntentType.none) {
      try {
        shouldExecuteCommand = await _aiService.verifyTorrentIntent(
          model: _activeModel,
          userMessage: text,
          timeout: const Duration(seconds: 2),
        );
      } catch (_) {
        shouldExecuteCommand = false;
      }
    }

    if (shouldExecuteCommand) {
      await _executeIntent(parsed);
    }

    await _sendToAi(text, auto: false, visibleUserMessage: true);
  }

  Future<void> _executeIntent(TorrentIntent intent) async {
    switch (intent.type) {
      case TorrentIntentType.search:
        if (intent.payload.isNotEmpty) {
          _searchController.text = intent.payload;
          await _performSearch(intent.payload);
        }
        break;
      case TorrentIntentType.downloadTop:
        if (_results.isNotEmpty) {
          await _startDownload(_results.first);
        }
        break;
      case TorrentIntentType.whatsDownloading:
        break;
      case TorrentIntentType.safetyCheck:
        break;
      case TorrentIntentType.betterVersion:
        if (_selected != null) {
          await _performSearch('${_selected!.name} 1080p verified');
        }
        break;
      case TorrentIntentType.diskSpace:
        final usedByLibrary = _contextService.library.fold<int>(
          0,
          (sum, item) => sum + (item.totalSize ?? 0),
        );
        final info =
            'Local library currently uses about ${_formatSize(usedByLibrary)}.';
        setState(() {
          _messages.add(
            AiChatEntry(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              role: 'assistant',
              content: info,
              createdAt: DateTime.now(),
              isAutoTriggered: true,
            ),
          );
        });
        _scrollChatToBottom();
        break;
      case TorrentIntentType.none:
        break;
    }
  }

  Future<void> _sendToAi(
    String prompt, {
    required bool auto,
    required bool visibleUserMessage,
  }) async {
    if (!SettingsService.instance.enableAiCopilot) {
      return;
    }

    setState(() {
      _isSending = true;
      if (visibleUserMessage) {
        _messages.add(
          AiChatEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            role: 'user',
            content: prompt,
            createdAt: DateTime.now(),
          ),
        );
      }
      _messages.add(
        AiChatEntry(
          id: 'assist-${DateTime.now().microsecondsSinceEpoch}',
          role: 'assistant',
          content: '',
          createdAt: DateTime.now(),
          isAutoTriggered: auto,
          isStreaming: true,
        ),
      );
    });
    _scrollChatToBottom();

    final contextBlock = _contextService.getContext();
    final history = _messages
        .where((m) => !m.isStreaming && m.content.trim().isNotEmpty)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final payload = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
        'You are Vault The Spire AI, an in-app torrent copilot. '
            'Always use the provided app context and reference live torrent state.',
      },
      {'role': 'system', 'content': contextBlock},
      ...history,
      {'role': 'user', 'content': prompt},
    ];

    try {
      final stream = await _aiService.chatChunkStream(
        model: _activeModel,
        messages: payload,
      );
      if (mounted && !_aiReady) {
        setState(() {
          _aiReady = true;
        });
      }
      final buffer = StringBuffer();
      var sawDone = false;
      _pendingStreamText = '';
      await for (final chunk in stream) {
        buffer.write(chunk.content);
        if (chunk.done) {
          sawDone = true;
        }
        if (!mounted) return;
        _queueStreamingAssistantText(buffer.toString());
        if (chunk.done) break;
      }

      if (!mounted) return;
      _queueStreamingAssistantText(buffer.toString(), force: true);
      setState(() {
        final index = _messages.lastIndexWhere(
          (m) => m.isStreaming && m.role == 'assistant',
        );
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(
            content: sawDone
                ? _messages[index].content
                : '${_messages[index].content} [connection lost]',
            isStreaming: false,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiReady = false;
        final index = _messages.lastIndexWhere(
          (m) => m.isStreaming && m.role == 'assistant',
        );
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(
            content:
                'AI copilot offline  -  check your Ollama connection in Settings. ($e)',
            isStreaming: false,
          );
        }
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      if (_queuedAutoEvents.isNotEmpty) {
        final next = _queuedAutoEvents.removeAt(0);
        unawaited(
          _sendToAi(next.prompt, auto: true, visibleUserMessage: false),
        );
      }
      _scrollChatToBottom();
    }
  }

  Future<void> _checkAiReadiness() async {
    if (!SettingsService.instance.enableAiCopilot) {
      if (!mounted) return;
      setState(() {
        _aiReady = false;
      });
      return;
    }
    final ok = await _aiService.checkVersion();
    if (!mounted) return;
    setState(() {
      _aiReady = ok;
    });
  }

  Future<void> _syncAiSettings() async {
    final currentUrl = SettingsService.instance.aiOllamaUrl;
    final currentModel = SettingsService.instance.aiDefaultModel;

    if (_cachedAiUrl != currentUrl || _cachedAiModel != currentModel) {
      if (_cachedAiUrl != currentUrl) {
        _aiService.setBaseUrl(currentUrl);
        _cachedAiUrl = currentUrl;
        _aiReady = false; // Reset ready status when URL changes
        // Verify connection with new URL
        final ok = await _aiService.checkVersion();
        if (mounted) {
          setState(() {
            _aiReady = ok;
          });
        }
      }
      if (_cachedAiModel != currentModel) {
        _activeModel = currentModel;
        _cachedAiModel = currentModel;
      }
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<FullModeAccess>();
    final isNarrow = MediaQuery.of(context).size.width < 900;

    final torrentPane = _buildTorrentPane(context);
    final chatPane = _buildChatPane(context);

    Widget content;
    if (_focusMode) {
      content = torrentPane;
    } else if (_chatMode) {
      content = Row(
        children: [
          SizedBox(width: 220, child: torrentPane),
          const VerticalDivider(width: 1),
          Expanded(child: chatPane),
        ],
      );
    } else if (isNarrow) {
      content = Column(
        children: [
          Expanded(flex: 6, child: torrentPane),
          const Divider(height: 1),
          Expanded(flex: 5, child: chatPane),
        ],
      );
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) {
          final left = constraints.maxWidth * _splitRatio;
          return Row(
            children: [
              SizedBox(width: left, child: torrentPane),
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _splitRatio =
                          ((_splitRatio * constraints.maxWidth) +
                              details.delta.dx) /
                          constraints.maxWidth;
                      _splitRatio = _splitRatio.clamp(0.3, 0.75);
                    });
                  },
                  child: Container(
                    width: 8,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              Expanded(child: chatPane),
            ],
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault The Spire AI'),
        actions: [
          IconButton(
            tooltip: 'Focus mode',
            onPressed: () => setState(() {
              _focusMode = !_focusMode;
              if (_focusMode) {
                _chatMode = false;
              }
            }),
            icon: Icon(_focusMode ? Icons.view_week : Icons.filter_none),
          ),
          IconButton(
            tooltip: 'Chat mode',
            onPressed: () {
              setState(() {
                _chatMode = !_chatMode;
                if (_chatMode) {
                  _focusMode = false;
                }
              });
              if (_chatMode) {
                _syncAiSettings();
                if (!_aiReady) {
                  _checkAiReadiness();
                }
              }
            },
            icon: Icon(_chatMode ? Icons.chat : Icons.open_in_full),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildTorrentPane(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeDownloads = _torrentStates.where((t) {
      final state = t.state.toLowerCase();
      return state.contains('download') ||
          state.contains('seed') ||
          state.contains('queue') ||
          state.contains('pending_metadata');
    }).toList();
    final library = _torrentStates.where((t) => t.isComplete).toList();
    final hasSearchResults = _results.isNotEmpty;

    return Container(
      color: cs.surface,
      child: DefaultTextStyle(
        style: TextStyle(color: cs.onSurfaceVariant),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 720;
                  final categoryPicker = DropdownButton<String>(
                    value: _category,
                    isDense: true,
                    dropdownColor: cs.surfaceContainerHighest,
                    items:
                        const [
                              'All',
                              'Movies',
                              'TV',
                              'Music',
                              'Software',
                              'Books',
                            ]
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _category = value;
                      });
                      _contextService.updateCategory(value);
                      _triggerAutoEvent(_triggers.onCategoryChanged(value));
                    },
                  );

                  final createButton = FilledButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CreateTorrentScreen(),
                        ),
                      );
                      if (!mounted) return;
                      await _refreshTorrents();
                    },
                    child: const Text('Create Torrent'),
                  );

                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'Search torrents',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onSubmitted: _performSearch,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            categoryPicker,
                            createButton,
                          ],
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            labelText: 'Search torrents',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onSubmitted: _performSearch,
                        ),
                      ),
                      const SizedBox(width: 8),
                      categoryPicker,
                      const SizedBox(width: 8),
                      createButton,
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              if (_resolvingMagnet)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Resolving metadata...'),
                    ],
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 720;
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _magnetController,
                          decoration: const InputDecoration(
                            hintText: 'Paste magnet link',
                          ),
                          onSubmitted: (_) => _addMagnet(),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed: _addMagnet,
                            icon: const Icon(Icons.add_link),
                            label: const Text('Add'),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _magnetController,
                          decoration: const InputDecoration(
                            hintText: 'Paste magnet link',
                          ),
                          onSubmitted: (_) => _addMagnet(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        onPressed: _addMagnet,
                        icon: const Icon(Icons.add_link),
                        label: const Text('Add'),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'Torrents',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: activeDownloads.isEmpty && library.isEmpty
                      ? const Center(
                          child: Text(
                            'No active torrents yet. Add a magnet link or start one from search.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: [
                            if (activeDownloads.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(12, 4, 12, 6),
                                child: Text(
                                  'Download queue',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            for (final item in activeDownloads)
                              RepaintBoundary(
                                child: Builder(
                                  builder: (context) {
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        item.model.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          '${item.statusLabel} • ${item.peers} peers',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            if (library.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
                                child: Text(
                                  'Completed',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            for (final item in library)
                              RepaintBoundary(
                                child: ListTile(
                                  dense: true,
                                  leading: Icon(
                                    Icons.check_circle_outline,
                                    size: 18,
                                    color: cs.primary,
                                  ),
                                  title: Text(
                                    item.model.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    item.model.filePath ?? 'Completed',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onTap: Platform.isWindows
                                      ? () {
                                          _triggeredEventKeys.remove(
                                            'download_completed:${item.model.name}',
                                          );
                                          _triggerAutoEvent(
                                            _triggers.onDownloadCompleted(
                                              item.model.name,
                                            ),
                                          );
                                        }
                                      : null,
                                ),
                              ),
                          ],
                        ),
                ),
              ),
              if (hasSearchResults) ...[
                const SizedBox(height: 10),
                const Text(
                  'Search results',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      final selected = _selected?.torrentId == item.torrentId;
                      final safeTitle = item.name.length > 60
                          ? '${item.name.substring(0, 60)}...'
                          : item.name;
                      final stats = <String>[];
                      if ((item.seeders ?? 0) > 0) {
                        stats.add('S: ${item.seeders}');
                      }
                      if ((item.leechers ?? 0) > 0) {
                        stats.add('L: ${item.leechers}');
                      }
                      final sl = stats.isEmpty ? '' : stats.join(' / ');
                      final age = item.ageYears == null
                          ? ' - '
                          : (item.ageYears == 0
                                ? 'this year'
                                : '${item.ageYears} years ago');
                      final source = item.source.isEmpty ? ' - ' : item.source;
                      return Card(
                        color: selected
                            ? cs.secondaryContainer
                            : cs.surfaceContainerLow,
                        child: RepaintBoundary(
                          child: ListTile(
                            title: Text(
                              safeTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${sl.isEmpty ? '' : '$sl | '}Size ${item.size == null ? ' - ' : _formatSize(item.size!)} | Source $source | Age $age',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                            onTap: () => _selectResult(item),
                            trailing: IconButton(
                              onPressed: () => _startDownload(item),
                              icon: const Icon(Icons.download),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final cs = Theme.of(context).colorScheme;
    Color trustColor;
    switch (_trustSignal) {
      case 'Green':
        trustColor = const Color(0xFF4CAF50);
        break;
      case 'Red':
        trustColor = const Color(0xFFF44336);
        break;
      case 'Neutral':
        trustColor = const Color(0xFF9E9E9E);
        break;
      default:
        trustColor = const Color(0xFFFFC107);
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'AI Info Card',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: trustColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _trustSignal,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_infoCardLoading)
            const LinearProgressIndicator()
          else
            Text(_infoCardText, maxLines: 4, overflow: TextOverflow.ellipsis),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _selected == null
                  ? null
                  : () {
                      _chatController.text =
                          'Tell me more about ${_selected!.name}';
                    },
              child: const Text('Tell me more'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPane(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aiEnabled = SettingsService.instance.enableAiCopilot;
    return Container(
      color: cs.surfaceContainerLowest,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: _aiReady ? cs.tertiaryContainer : cs.errorContainer,
            child: Text(
              _aiReady
                  ? 'AI Ready'
                  : aiEnabled
                  ? 'AI copilot offline  -  check your Ollama connection in Settings'
                  : 'AI Copilot disabled in Settings',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _aiReady ? cs.onTertiaryContainer : cs.onErrorContainer,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _chatScroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.48,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? cs.primaryContainer
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: msg.isAuto
                          ? Border.all(
                              color: cs.tertiary,
                              width: 1.3,
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.isAuto)
                          Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.bolt,
                                  size: 14,
                                  color: cs.tertiary,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Auto',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.tertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        MarkdownBody(
                          data: msg.content.isEmpty && msg.isStreaming
                              ? '...'
                              : msg.content,
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(
                                Theme.of(context),
                              ).copyWith(
                                p: TextStyle(color: cs.onSurface),
                                code: const TextStyle(
                                  fontFamily: 'monospace',
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_selected != null || _infoCardLoading)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: _buildInfoCard(),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                      ),
                      onSubmitted: (_) => _onUserSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isSending || !aiEnabled ? null : _onUserSend,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}